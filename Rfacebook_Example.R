######## Installing the Rfacebook package
install.packages("Rfacebook")
library(Rfacebook)

######## Setting up Facebook authentication
# Get FB Token (2 hrs temp access)
# https://developers.facebook.com/tools/explorer
token <- "xxxxxxxxxxxxxxxx"
require("Rfacebook")
fb_oauth <- fbOAuth(app_id="xxxxx",app_secret="xxxxxxxxxx",extended_permissions = TRUE)

save(fb_oauth, file="fb_oauth")
load("fb_oauth")

######### Grab Facebook Page Posts
ntucPosts <- getPage("thatsmyfairprice", token, n = 5000, reactions = T)

####################################################
########           FB Post Type           ##########
####################################################

######## Check Distribution of Post Type
table(ntucPosts$type)
plot(table(ntucPosts$type),ylab="Count of Post Type")

######## Check Distribution of Likes & Reactions in each Post Type
install.packages("sqldf")
library(sqldf)
postType <- sqldf("select type, count(type) as total_type_count,
                  sum(shares_count) as total_shares,
                  sum(likes_count) as total_likes, 
                  sum(love_count) as total_love,
                  sum(haha_count) as total_haha,
                  sum(wow_count) as total_wow,
                  sum(sad_count) as total_sad,
                  sum(angry_count) as total_angry
                  from ntucPosts group by type")

######### Grab All Comments
ntucComment <- list()
for (i in 1:length(ntucPosts$id)){
  ntucComment[[i]] <- getPost(ntucPosts$id[i], token, likes=F, comments=T)
  ntucComment[[i]][['reactions']] <- getReactions(post=ntucPosts$id[i], token)
  if (nrow(ntucComment[[i]][["comments"]]) == 0)
    ntucComment[[i]][['comments']][1,] <- c(NA,NA,NA,NA,NA,NA,NA)
}
ntucComments <- do.call(rbind, lapply(ntucComment, data.frame, stringsAsFactors=FALSE))

######### Break scraping of comments into smaller parts if API calls fails
ntucComment01 <- list()
for (i in 1:ceiling(length(ntucPosts$id)/2)){
  ntucComment01[[i]] <- getPost(ntucPosts$id[i], token, likes=F, comments=T)
  ntucComment01[[i]][['reactions']] <- getReactions(post=ntucPosts$id[i], token)
  if (nrow(ntucComment01[[i]][["comments"]]) == 0)
    ntucComment01[[i]][['comments']][1,] <- c(NA,NA,NA,NA,NA,NA,NA)
}
ntucComment01DF <- do.call(rbind, lapply(ntucComment01, data.frame, stringsAsFactors=FALSE))

ntucComment02 <- list()
for (i in (ceiling(length(ntucPosts$id)/2)+1):length(ntucPosts$id)){
  ntucComment02[[i]] <- getPost(ntucPosts$id[i], token, likes=F, comments=T)
  ntucComment02[[i]][['reactions']] <- getReactions(post=ntucPosts$id[i], token)
  if (nrow(ntucComment02[[i]][["comments"]]) == 0)
    ntucComment02[[i]][['comments']][1,] <- c(NA,NA,NA,NA,NA,NA,NA)
}
ntucComment02DF <- do.call(rbind, lapply(ntucComment02, data.frame, stringsAsFactors=FALSE))

ntucComments <- rbind(ntucComment01DF, ntucComment02DF)
write.csv(ntucComments, file = "ntucComments.csv",row.names=FALSE)

# ntucComments[1:15,c("comments.message")]

######## Clean Up DF Names (replacing '.' with '_') for later use with SQLDF
names(ntucComments) <- gsub("\\.", "_", names(ntucComments))

######## Function to covert FB Date to GMT
format.facebook.date <- function(datestring) {
  date <- as.POSIXct(datestring, format = "%Y-%m-%dT%H:%M:%S+0000", tz="GMT")
}

######## Convert FB DateTime to GMT
ntucComments$comments_datetime <- format.facebook.date(ntucComments$comments_created_time)
ntucComments$post_datetime <- format.facebook.date(ntucComments$post_created_time)

####################################################
########          Data Cleaning           ##########
####################################################

######### convert to ASCII
ntucComments$comments_message <- iconv(ntucComments$comments_message, "ASCII", "UTF-8", sub="")

######### removing comments made by the organisation itself
ntucCommentsClean <- subset(ntucComments, comments_from_name != "NTUC FairPrice")

######## substituting emoticons with text/desc
ntucCommentsClean$comments_message <- gsub(":-)", " happy ", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub(";-)", " happy ", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub(":)", " happy ", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub(";)", " happy ", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub("=p", " happy ", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub(":p", " happy ", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub(":P", " happy ", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub("=P", " happy ", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub("=)", " happy ", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub(":-)", " happy ", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub("<3", " love ", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub(":\\(", " sad ", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub(":-\\(", " sad ", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub(":x", " oops ", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub(":X", " oops ", ntucCommentsClean$comments_message)

######## substituting line breaks, tabs, digits, url and punctuations with empty space
ntucCommentsClean$comments_message <- gsub("\n", " ", ntucCommentsClean$comments_message) 
ntucCommentsClean$comments_message <- gsub("\t", " ", ntucCommentsClean$comments_message) 
ntucCommentsClean$comments_message <- gsub("\\d", "", ntucCommentsClean$comments_message) 
ntucCommentsClean$comments_message <- gsub("http[^[:blank:]]+", "", ntucCommentsClean$comments_message)
ntucCommentsClean$comments_message <- gsub("[[:punct:]]", "", ntucCommentsClean$comments_message)

######## removing rows with less than 3 chars -> not useful at all for text analysis
ntucCommentsClean <- subset(ntucCommentsClean, nchar(comments_message) > 2)

####################################################
########    Lexicon Sentiment analysis    ##########
####################################################
positives = readLines("positive-words.txt")
negatives = readLines("negative-words.txt")

######## add custom abbreviation / internet slangs to lexicon 
positives = c(positives, 'thx', 'congrats')
negatives = c(negatives, 'wtf', 'cancellation')

install.packages("stringr")
install.packages("dplyr")
install.packages("plyr")
library(stringr)
library(dplyr)
library(plyr)

###### define function: sentiment analysis
score.sentiment = function(sentences, pos.words, neg.words, .progress='none')
{
  require(plyr)
  require(stringr)
  
  # we got a vector of sentences. plyr will handle a list
  # or a vector as an "l" for us
  # we want a simple array of scores back, so we use
  # "l" + "a" + "ply" = "laply":
  scores = laply(sentences, function(sentence, pos.words, neg.words) {
    
    # clean up sentences with R's regex-driven global substitute, gsub():
    sentence = gsub('[[:punct:]]', '', sentence)
    sentence = gsub('[[:cntrl:]]', '', sentence)
    sentence = gsub('\\d+', '', sentence)
    # and convert to lower case:
    sentence = tolower(sentence)
    
    # split into words. str_split is in the stringr package
    word.list = str_split(sentence, '\\s+')
    # sometimes a list() is one level of hierarchy too much
    words = unlist(word.list)
    
    # compare our words to the dictionaries of positive & negative terms
    pos.matches = match(words, pos.words)
    neg.matches = match(words, neg.words)
    
    # match() returns the position of the matched term or NA
    # we just want a TRUE/FALSE:
    pos.matches = !is.na(pos.matches)
    neg.matches = !is.na(neg.matches)
    
    # and conveniently enough, TRUE/FALSE will be treated as 1/0 by sum():
    score = sum(pos.matches) - sum(neg.matches)
    
    return(score)
  }, pos.words, neg.words, .progress=.progress )
  
  scores.df = data.frame(score=scores, text=sentences)
  return(scores.df)
}

ntucSentiScores <- score.sentiment(ntucCommentsClean$comments_message,positives,negatives,.progress = "text")

hist(ntucSentiScores$score,xlab="Sentiment Score",main="Histogram of Sentiment Scores")

ntucCommentsClean$sentiment <- ntucSentiScores$score
ntucCommentsClean$sentiment_polar <- ifelse(ntucCommentsClean$sentiment == 0, "Neutral", ifelse(ntucCommentsClean$sentiment > 0, "Positive", "Negative"))

####################################################
########  Sentiment analysis by Post Type  #########
####################################################
hist(ntucCommentsClean$sentiment, xlab = "Sentiment Score", main = "Sentiment Histogram of USP's posts")
table(ntucCommentsClean$sentiment_polar) 
plot(table(ntucCommentsClean$sentiment_polar),ylab="Frequency")
mean(ntucCommentsClean$sentiment)
sd(ntucCommentsClean$sentiment)

######## Sentiment by different post type
ntucLink <- subset(ntucCommentsClean, post_type == "link") 
hist(ntucLink$sentiment, xlab = "Sentiment Score", main = "Sentiment Histogram of USP's link posts")
table(ntucLink$sentiment_polar)
mean(ntucLink$sentiment)
sd(ntucLink$sentiment)

ntucPhoto <- subset(ntucCommentsClean, post_type == "photo") 
hist(ntucPhoto$sentiment, xlab = "Sentiment Score", main = "Sentiment Histogram of USP's photo posts")
table(ntucPhoto$sentiment_polar)
mean(ntucPhoto$sentiment)
sd(ntucPhoto$sentiment)

ntucStatus <- subset(ntucCommentsClean, post_type == "status") 
hist(ntucStatus$sentiment, xlab = "Sentiment Score", main = "Sentiment Histogram of USP's status posts")
table(ntucStatus$sentiment_polar)
mean(ntucStatus$sentiment)
sd(ntucStatus$sentiment)

ntucVideo <- subset(ntucCommentsClean, post_type == "video") 
hist(ntucVideo$sentiment, xlab = "Sentiment Score", main = "Sentiment Histogram of USP's video posts")
table(ntucVideo$sentiment_polar)
mean(ntucVideo$sentiment)
sd(ntucVideo$sentiment)


####################################################
########           Text analysis          ##########
####################################################
Needed = c("tm", "SnowballC", "RColorBrewer", "wordcloud")  
install.packages(Needed, dependencies=TRUE)

library(tm)
# create corpus
corpus = Corpus(VectorSource(ntucCommentsClean$comments_message))
# Conversion to lower case
corpus = tm_map(corpus, content_transformer(tolower)) 
# Removal of punctuation
corpus = tm_map(corpus, removePunctuation)
# Removal of numbers
corpus = tm_map(corpus, removeNumbers)
# Removal of stopwords
corpus = tm_map(corpus, removeWords, stopwords("english"))
# Stemming is done by:
library("SnowballC")
corpus = tm_map(corpus, stemDocument)  # don't do

##### Generate wordcloud
library(wordcloud)
wordcloud(corpus, random.order = F, min.freq=2, max.words=100,
          colors = brewer.pal(8, "Dark2"))


####################################################
########        Page Trend Analysis       ##########
####################################################

aggregate.matric <- function(metric){
  m <- aggregate(ntucPosts[[paste0(metric, "_count")]],
                 list(month = ntucPosts$month), 
                 mean)
  m$month <- as.Date(paste0(m$month, "-15"))
  m$metric <- metric
  return(m)
}

ntucPosts$timestamp <- format.facebook.date(ntucPosts$created_time)
ntucPosts$month <- format(ntucPosts$timestamp, "%Y-%m")

df.list <- lapply(c("likes", "comments", "shares"), aggregate.matric)
df <- do.call(rbind, df.list)

install.packages("ggplot2")
install.packages("scales")
library(ggplot2)
library(scales)

ggplot(df, aes(x = month, y = x, group = metric)) +
  geom_line(aes(color = metric)) +
  scale_x_date(date_breaks = "years", labels = date_format("%Y")) +
  scale_y_log10("Average count per post", breaks = c(100, 500, 1000)) +
  theme_bw() +
  theme(axis.title.x = element_blank(), axis.text.x=element_text(angle = -90, hjust = 0)) +
  ggtitle("NTUC Page CTR Performance") 


####################################################
########    Brand Post Day/Time Heatmap   ##########
####################################################

install.packages("lubridate")
library(lubridate)

ntucPosts$datetime <- format.facebook.date(ntucPosts$created_time)
ntucPosts$dayweek <- wday(ntucPosts$datetime, label=T)
ntucPosts$dayint <- wday(ntucPosts$datetime)
ntucPosts$sghour <- with_tz(ntucPosts$datetime, "Asia/Singapore")
ntucPosts$hour <- hour(ntucPosts$sghour)

install.packages("d3heatmap")
library(d3heatmap)
# Creating Matrix of Weekday by Time in 24 hours
# week day 1-7 maps to Sun-Sat
# hours 0-23 maps to 12am-11pm
heatmapFrame <- matrix(0,nrow=24,ncol=7);
rownames(heatmapFrame) <- 0:23
colnames(heatmapFrame) <- c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")

for (i in 1:24) {
  for (j in 1:7) {
    heatmapFrame[i,j] <- nrow(subset(ntucPosts,dayint==j & hour==i-1))
  }
}
d3heatmap(heatmapFrame, scale = "column",dendrogram = "none", color = scales::col_quantile("Blues", NULL, 5))

####################################################
######  Consumers Comments Day/Time Heatmap  #######
####################################################
ntucCommentsClean$comments_datetime <- format.facebook.date(ntucCommentsClean$comments_created_time)
ntucCommentsClean$dayweek <- wday(ntucCommentsClean$comments_datetime, label=T)
ntucCommentsClean$dayint <- wday(ntucCommentsClean$comments_datetime)
ntucCommentsClean$sghour <- with_tz(ntucCommentsClean$comments_datetime, "Asia/Singapore")
ntucCommentsClean$hour <- hour(ntucCommentsClean$sghour)

# Creating Matrix of Weekday by Time in 24 hours
# week day 1-7 maps to Sun-Sat
# hours 0-23 maps to 12am-11pm
heatmapFrame <- matrix(0,nrow=24,ncol=7);
rownames(heatmapFrame) <- 0:23
colnames(heatmapFrame) <- c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")

for (i in 1:24) {
  for (j in 1:7) {
    heatmapFrame[i,j] <- nrow(subset(ntucCommentsClean,dayint==j & hour==i-1))
  }
}
d3heatmap(heatmapFrame, scale = "column",dendrogram = "none", color = scales::col_quantile("Blues", NULL, 5))


####################################################
########      Brands posts frequency      ##########
####################################################

time.interval <- min(ntucPosts$datetime) %--% max(ntucPosts$datetime)
sampledays <- round(time.interval / ddays(1))

ntucPostFreq <- sampledays / nrow(ntucPosts)
## 10.32


####################################################
########        Frequency analysis        ##########
####################################################
# Creating Term-Document Matrices From Corpus
dtm = DocumentTermMatrix(corpus)

#### Operations on Term-Document Matrices
# we can find those terms that occur at least five times
findFreqTerms(dtm, 30)

#####get the frequency table of each terms
freq <- colSums(as.matrix(dtm)) 
m = as.matrix(dtm)
# https://rstudio-pubs-static.s3.amazonaws.com/31867_8236987cf0a8444e962ccd2aec46d9c3.html
wf <- data.frame(word=names(freq), freq=freq)  

# get word counts in decreasing order
word_freqs = sort(rowSums(m), decreasing = TRUE) 
# create a data frame with words and their frequencies
dm = data.frame(word = names(word_freqs), freq = word_freqs)

####################################################
########     Topic Modelling with LDA     ##########
####################################################
install.packages("modeltools")
devtools::install_github("kasperwelbers/corpus-tools")
library(corpustools)

#### k=10: number of topics
set.seed(2008)
m = lda.fit(dtm, K=3, num.iterations=1000)
terms(m,15)
install.packages("LDAvis")
library(LDAvis)
install.packages("proxy")
library(proxy)
serVis(ldavis_json(m, dtm))
