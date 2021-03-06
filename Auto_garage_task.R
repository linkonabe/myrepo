
---
  title: "Local Garage Customer Churn"
  output: "R script"
---

library(data.table) # Fast I/O
library(tidyverse)# Data munging
library(ggplot2)
theme_set(theme_minimal())
library(dplyr)# Data munging
library(lubridate) # Make dates easy
library(caret) # Handy ML functions
library(corrplot)
setwd("./R Dictory/Acxion_Rproj")

cust_tab <- fread("acx_cust_table.csv", header = T) # customer table
prod_tab <- read.csv("acx_product_table.csv", header = T) # product table
trans_tab <- fread("acx_trans_table.csv", header = T) # transaction table

#Data Wrangling
df <- trans_tab[cust_tab, on = "customer_id"]

##Now lets look for missing values. 
df %>% map(~ sum(is.na(.)))
#About 2039 rows are missing from 4 variables. This has to be dealt with.

df<-na.omit(df)# removing missing rows.

#checking that the imputation worked
sum(is.na(df))
#merge product table

data <- merge(df, prod_tab, by.x = "product_id", by.y = "product_id", all.x = TRUE) #using nerge function to replicate vlooup
data$trans_date<- dmy_hms(data$trans_date,tz=Sys.timezone()) # convert the datetime from character

data$churn_num <- as.numeric(data$churn) #create a numeric variable from logical churn. 
summary(data)
#from the summary of the data, the average age of customers is 53 years old and 85% of customers churned. clients starting price on services is £10 and could be as high as £1000.

##Exploratory Data Analysis

#Customer churn can be characterized as either contractual or non-contractual. It can also be characterized as voluntary or non-voluntary depending on the cancellation mechanism. 
#From this dataset, business and customer relationshop is non contractual as customers could walk out of service anytime.

#To guide the analysis, I’m going to try and answer the following questions about the customer segments:
#1. Are men more likely to churn than women?
#2. Are particular car type owner to churn more?
#3. How frequent are customers visit to garage?
#4. When are customers likely to churn, 


#I’ll start with gender. I wouldn’t expect one gender to be more likely than another to churn, but lets see what the data shows
ggplot(data) +
  geom_bar(aes(x = sex, fill = churn), position = "dodge")
#Taking a look, the results are similar. Roughly one quarter of the male customers churn, and roughly one quarter of the female customers churn. 
#We can also take a look at exactly how many people from each gender churned.
data %>%
  group_by(sex,churn) %>%
  summarise(n=n())
#Next I’ll take a look at car type and impact on churn. 
ggplot(data) +
  geom_bar(aes(x = car_type, fill = churn), position = "dodge")
#Not enough inference could be deduced from this plot. let drill further 
data %>%
  group_by(car_type) %>%
  summarise(n = n()) %>%
  mutate(freq = n / sum(n))

data %>%
  group_by(car_type, churn) %>%
  summarise(n = n()) %>%
  mutate(freq = n / sum(n))
#This variable shows a much more meaningful relationship. Majority of customers are Mercedes and Ford owners. Apart from 47% of Audi-owned customers who churned, 
#all different car_type customers who churned are not more than 12% . These results show that Audi owned customers are much more likely to churn.
# Now, does "Audi"  generates more revenue than other types of cars?
 data %>% group_by(car_type) %>% summarise (totalRevenue = sum(quantity *product_cost)) 
 # Mercedes and Ford has the highest revenue, with a combine value of £4.7m. this is about 44% of total revenue. closely followed by VolsWagen. 
 data %>% group_by(product_desc) %>% summarise (n = n(), totalRevenue = sum(quantity *product_cost))
#Chunk amount of revenue (£6.96m) Was realised from repaint while valet only generated £69k.
 
 ggplot(data) +
   geom_bar(aes(x = quantity, fill = churn), position = "dodge")

 #Another useful visualization is the box and whisker plot. This gives us a little bit more compact visual of our data, and helps us identify outliers. 
 #Lets take a look at some box and whisker plots for totalspent of the different customer segments.
 
data %>% 
  mutate(totalspent = quantity * product_cost) %>%
 ggplot(aes(x = churn, y = totalspent, colour =  sex)) + facet_wrap(~ sex) +
geom_point(alpha = 0.3, position = "jitter") +
  geom_boxplot(alpha = 0, colour = "black")

 #We can see that exist outliers across the spending of customers both churners and non-churned

#Churn over the year
 
 
 ##Modelling

##1. Anomaly Detection
#churn modelling in non-contractual business is often times an anomaly detection problem.
# In order to determine when customers are churning or likely to churn, we need to know when they are displaying anomalously large between purchase times.
#Using Anomolous detection to model churn, We want to be able to make claims like “9 times out of 10, Customer X will visit the garage for repair or some sort within Y days”. 
#If Customer X does not make another purchase within Y days, we know that there is only a 1 in 10 chance of this happening, and that this behaviour is anomalous. 

 anom.data <- data 
 anom.data$total_spent <- anom.data$product_cost * anom.data$quantity #create a dataframe for for each customer’s total spend per day.   
 

 txns <- anom.data %>% 
   mutate(customer_id = as.factor(customer_id),
          trans_date = trans_date) %>%
   group_by(customer_id, trans_id, trans_date) %>% 
   summarise(Spend = sum(total_spent)) %>%
   ungroup() %>% 
   filter(Spend>0)
 
 time_between <- txns %>% 
   arrange(customer_id, trans_date) %>% 
   group_by(customer_id) %>% 
   mutate(dt = as.numeric(trans_date - lag(trans_date), unit=  'days')) %>% 
   ungroup() %>% 
   na.omit()
  
 #At this time, we are only interested in customers who have made at least 3 visits to the garage. This customers are likely to come again
 Ntrans = txns %>% 
   group_by(customer_id) %>% 
   summarise(N = n())%>% 
   filter(N>4) 
 
 
 #Create a little function for randomly sampling customers.
 sample_n_groups = function(tbl, size, replace = FALSE, weight = NULL) {
   grps = tbl %>% groups %>% lapply(as.character) %>% unlist
   keep = tbl %>% summarise() %>% ungroup() %>% sample_n(size, replace, weight)
   tbl %>% right_join(keep, by=grps) %>% group_by_(.dots = grps)
 }
 
 ecdf_df <- time_between %>% group_by(customer_id) %>% arrange(dt) %>% mutate(e_cdf = 1:length(dt)/length(dt))
 
 sample_users <- ecdf_df %>% inner_join(Ntrans) %>% sample_n_groups(15)

 ggplot(data = time_between %>% inner_join(Ntrans) %>% filter(customer_id %in% sample_users$customer_id), aes(dt)) + 
   geom_histogram(aes(y = ..count../sum(..count..)), bins = 15) + 
   facet_wrap(~customer_id) +
   labs(x = 'Time Since Last Purchase (Days)',y = 'Frequency')
 
 #After calculating ECDF for every customer, we are visualizing the above customers’ ECDF. The red line represents approximate 90 percentile. 
 #So if the ECDF crosses the red line at 20 days, this means 9 times out of 10 that customer will make another purchase within 20 days
 
 ggplot(data = ecdf_df %>% inner_join(Ntrans) %>% filter(customer_id %in% sample_users$customer_id), aes(dt,e_cdf) ) + 
   geom_point(size =0.5) +
   geom_line() + 
   geom_hline(yintercept = 0.9, color = 'red') + 
   facet_wrap(~customer_id) +
   labs(x = 'Time Since Last Purchase (Days)')
 
 #Create a function to calculate 90th percentile.
 
 getq <- function(x,a = 0.9){
   if(a>1|a<0){
     print('Check your quantile')
   }
   X <- sort(x)
   e_cdf <- 1:length(X) / length(X)
   aprx = approx(e_cdf, X, xout = c(0.9))
   return(aprx$y)
 }
 
 percentiles = time_between %>% 
   inner_join(Ntrans) %>% 
   filter(N>2) %>% 
   group_by(customer_id) %>% 
   summarise(percentile.90= getq(dt)) %>% 
   arrange(percentile.90)
 
 #Looking at CustomerID
 percentiles[ which(percentiles$customer_id==745), ]
 
 #The model tells us: 9 times out of 10, CustomerID 745 will make a repair visit to the garage within 80.7days, If CustomerID 745 does not make another visit within 80.7 days, 
 #we know that there is only a 1 in 10 chance of this happening, and that this behaviour is anomalous. At this point, we know that CustomerID 745 begins to act “anomalously”.
 
 #Let’s have a quick snapshot of CustomerID 745’s purchase history to see whether our model makes sense:
   
   txns[ which(txns$customer_id==745), ]
 
   
 #Churn is very different for non-contractual businesses. The challenge lies in defining a clear churn event which means taking a different approach to modelling churn. 
#When a customer has churned, his (or her) time between purchases or visits is anomalously large, so we should have an idea of what “anomalously” means for each customer. 
#Using the ECDF, we have estimated the 90 percentile of each customers between purchase time distribution in a non-parametric way. By examining the last time a customer has made purchase, 
#and if the time between then and now is near the 90th percentile then we can call them “at risk for churn” and take appropriate action to prevent them from churning
   
  
##2. Classification Models
# It is generally believed that churn is a classification problem. Let us also predict churn with classification models such as
#1. Logistic regression  
#2. Randomforest
   
  set.seed(23)
  model.data <- anom.data
  model.data$churn_num <- as.factor(model.data$churn_num)
    model.data$car_type <- as.factor(model.data$car_type)
    model.data$sex <- as.factor(model.data$sex)
    model.data$trans_date <- as.factor(model.data$trans_date)
  idx <- sample(1:nrow(model.data),4000)
  train.df <- model.data[-idx,]
  test.df <- model.data[idx,]
   
  
 glm.model<- glm(churn_num ~ product_id + trans_date + quantity + age + sex + car_type +  
                   product_desc + product_cost+ total_spent, data = train.df, family = binomial(link="logit"), control = list(maxit = 50))
  summary(glm.model)
#shocking results. Many of these variables are not statistically significant.
# Let's choose those that significant and re-run the regression.

glm.model<- glm(churn_num ~ age + sex + car_type, data = train.df, family = binomial(link="logit"), control = list(maxit = 50))
rf.data <- train.df
rf.data$predictedLR1 <- predict.glm(glm.model, newdata=rf.data,type="response")
ROCpred <- prediction(rf.data$predictedLR1, rf.data$churn_num)
ROCperf <- performance(ROCpred,'tpr','fpr')
plot(ROCperf)

auc <- performance(ROCpred, measure="auc")
auc <- auc@y.values[[1]]
auc

#RandomForest

forest.model <- randomForest(churn_num ~ product_id + trans_date + quantity + age + sex + car_type +  product_desc + 
                            product_cost+ total_spent, data = train.df, ntree=100, 
                            type="classification")

trainRFmodel1<- randomForest(churn_num ~product_id + trans_date + quantity + age + sex + car_type +  product_desc + 
                               product_cost+ total_spent, 
             data = rf.data, importance= TRUE, ntree=1000)

predictions <- as.vector(trainRFmodel1$votes[,2])
rf.data$predictRF <- predictions
ROCRpredwholeRandom <- prediction(rf.data$predictRF,rf.data$churn_num)
ROCRperfwholeRandom <- performance(ROCRpredwholeRandom,'tpr','fpr')
plot(ROCRperfwholeRandom)

aucwholeRandom <- performance(ROCRpredwholeRandom,measure='auc')
aucwholeRandom <- aucwholeRandom@y.values[[1]]
aucwholeRandom


##GRADIENT BOOSTING TREES (GBT)
trainGBMmodel <- gbm(churn_num ~ product_id + quantity + age + sex + car_type +  product_desc + 
                     total_spent, data = rf.data,
distribution= "gaussian",n.trees=1000,shrinkage = 0.01,interaction.depth=4)
summary(trainGBMmodel)
# the most important factor to predict churn are "Age" and "car_type", followed by 4 other variables which relevance is insignificant.
gbm.test.df <- test.df
rf.data$predGBM <- predict(trainGBMmodel,rf.data,n.trees=1000)
ROCRpredGBM <- prediction(rf.data$predGBM, rf.data$churn_num)
ROCRperfGBM <- performance(ROCRpredGBM,'tpr','fpr')
plot(ROCRperfGBM)

#get GBM AUC
aucGBM <- performance(ROCRpredGBM,measure='auc')
aucGBM <- aucGBM@y.values[[1]]
aucGBM #best performing model 

#Performance Comparisons for the train set
m <- matrix(c(auc,aucwholeRandom,aucGBM),nrow=3,ncol=1)
colnames(m) <- c("AUC Value")
rownames(m) <- c("Logistic Regression","Random Forest","Gradient Boosting")
m


plot(ROCperf, col="red",colorsize = TRUE, text.adj = c(-.2,1.7), main=" Axciom AUC Curves - 3 Models")
plot(ROCRperfwholeRandom,add=TRUE,col="green", colorsize = TRUE, text.adj = c(-.2,1.7))
plot(ROCRperfGBM,add=TRUE,col="black", colorsize = TRUE, text.adj = c(-.2,1.7))
labels <- c("GLM: AUC=70.20%","Random Forest: AUC=81%", "Gradient Boosting: AUC=83.54%")
legend("bottom",xpd=TRUE,inset=c(0,0),labels,bty="n",pch=1,col=c("red","green","blue","black"))

#CHOOSING MODEL:
#According to the AUC curves, the method that gives us the most accurate model is gradient boosting with AUC value of 83.54%.

#Performance analysis for the test set using the best model.

testGBMmodel <- gbm(churn_num ~ product_id + quantity + age + sex + car_type +  product_desc + 
                       total_spent, data = test.df,
                     distribution= "gaussian",n.trees=1000,shrinkage = 0.01,interaction.depth=4) #Let apply GBM to the test set.
summary(testGBMmodel)

test.df$predGBM <- predict(testGBMmodel,test.df,n.trees=1000)
ROCRpredTestGBM <- prediction(test.df$predGBM, test.df$churn_num)
ROCRperfTestGBM <- performance(ROCRpredTestGBM,'tpr','fpr')
plot(ROCRperfTestGBM)

#AUC for GBM testset
aucTestGBM <- performance(ROCRpredTestGBM,measure="auc")
aucTestGBM <- aucTestGBM@y.values[[1]]
aucTestGBM 
#86% is the best model.

a <- matrix(c("The Best Model","Good Model","Underperforming"),nrow=3,ncol=1)
colnames(a) <- c("General Performance (Accuracy) of the algorithms")
rownames(a) <- c("Gradient Boosting","Random Forest","Logistic Regression")
a
