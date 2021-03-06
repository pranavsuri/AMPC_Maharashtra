## ----global_options, include=FALSE---------------------------------------
knitr::opts_chunk$set(fig.path='Figs/',
                      warning=FALSE, message=FALSE)

## ----echo=FALSE, message=FALSE, warning=FALSE, packages------------------
# Data handling
library(stringr)
library(dplyr)
library(data.table)

# Time series
library(xts)
library(forecast)
library(tseries)

# Visualization
library(ggplot2)
library(ggpubr)
library(gridExtra)

## ---- echo=FALSE, warning=FALSE, message=FALSE---------------------------
library("kableExtra")
print_table <- function(df){
  kable(df) %>%
    kable_styling(bootstrap_options = c("hover", "condensed", "responsive"),
                  font_size = 12)
}

## ---- reading_files------------------------------------------------------
msp = read.csv("CMO_MSP_Mandi.csv")
monthly_data = read.csv("Monthly_data_cmo.csv")

## ---- first_view---------------------------------------------------------
print_table(head(msp))
print_table(head(monthly_data))

## ---- cleaning_commodities-----------------------------------------------
msp$commodity = trimws(tolower(str_replace_all(msp$commodity, "[[:punct:]]", "")))
monthly_data$Commodity = trimws(tolower(str_replace_all(monthly_data$Commodity, "[[:punct:]]", "")))

## ------------------------------------------------------------------------
# Ordering data based on 'commodity' attribute
msp = msp[order(msp$commodity),]
length(unique(msp$commodity))

## ----message=FALSE, warning=FALSE----------------------------------------
monthly_data = monthly_data[order(monthly_data$Commodity),]

# Getting common commodities
common_comm = intersect(monthly_data$Commodity, msp$commodity)

# Monthly data of commodities whose MSP is available
monthly_data_MSP = monthly_data[monthly_data$Commodity %in% common_comm, ]
monthly_data_MSP$Commodity = factor(monthly_data_MSP$Commodity)
monthly_data_MSP$APMC = factor(monthly_data_MSP$APMC)

## str(monthly_data_MSP)

## ----outlier_removal_function, message=FALSE, warning=FALSE--------------
# Function to remove outliers
detect_outlier <- function(modal_price, Commodity){ 
  x = NULL
  a = tapply(modal_price, Commodity, quantile, probs = 0.75)
  b = tapply(modal_price, Commodity, quantile, probs = 0.25)
  out1 = a + 1.5 * (a-b)
  out2 = b - 1.5 * (a-b)

  for(i in 1:length(modal_price)){
    if((modal_price[i] > out1[Commodity[i]]) 
        || (modal_price[i] < out2[Commodity[i]])){
      x[i] = TRUE
    } 
    else{
      x[i] = FALSE
    }
  }
  return(x)
}

# Year-wise splitting the data
monthly_data_MSP2014 = filter(monthly_data_MSP, Year == 2014)
monthly_data_MSP2015 = filter(monthly_data_MSP, Year == 2015)
monthly_data_MSP2016 = filter(monthly_data_MSP, Year == 2016)

# Removing & saving outliers from the dataset
monthly_data_MSP2014$outlier = detect_outlier(monthly_data_MSP2014$modal_price, 
                                      monthly_data_MSP2014$Commodity)
monthly_data_MSP2015$outlier = detect_outlier(monthly_data_MSP2015$modal_price, 
                                      monthly_data_MSP2015$Commodity)
monthly_data_MSP2016$outlier = detect_outlier(monthly_data_MSP2016$modal_price, 
                                      monthly_data_MSP2016$Commodity)

outlier_file = rbind(monthly_data_MSP2014[monthly_data_MSP2014$outlier == T,],
                     monthly_data_MSP2015[monthly_data_MSP2015$outlier == T,],
                     monthly_data_MSP2016[monthly_data_MSP2016$outlier == T,])
write.csv(outlier_file, "Outliers.csv")

# Updating dataset after removing outliers
monthly_data_MSP2014 = monthly_data_MSP2014[monthly_data_MSP2014$outlier == F,
                            colnames(monthly_data_MSP2014)[colnames(monthly_data_MSP2014) != 'outlier']]
monthly_data_MSP2015 = monthly_data_MSP2015[monthly_data_MSP2015$outlier == F,
                            colnames(monthly_data_MSP2015)[colnames(monthly_data_MSP2015) != 'outlier']]
monthly_data_MSP2016 = monthly_data_MSP2016[monthly_data_MSP2016$outlier == F,
                            colnames(monthly_data_MSP2016)[colnames(monthly_data_MSP2016) != 'outlier']]

rm(monthly_data_MSP)
monthly_data_MSP = rbind(monthly_data_MSP2014, 
                         monthly_data_MSP2015,
                         monthly_data_MSP2016)

## ----detecting_seasonality, message=FALSE, warning=FALSE-----------------
# Helper functions
ssacf <- function(x) sum(acf(x,na.action=na.pass, plot=FALSE)$acf^2)
compare_ssacf <- function(add, mult) ifelse(ssacf(add) < ssacf(mult), 
                                           "Additive", "Multiplicative")

temp_data = as.data.table(monthly_data_MSP)

# Function to detect seasonality
seasonality_type <- function(dt){
  dt[, trend := rollmean(modal_price, 12, fill="extend", align = "right")]
  dt[, `:=`(detrended_a = modal_price - trend, detrended_m = modal_price/trend)]
  dt[, `:=` (seasonal_a = mean(detrended_a, na.rm = TRUE),
             seasonal_m = mean(detrended_m, na.rm = TRUE)), by=.(Month)]
  dt[is.infinite(seasonal_m), seasonal_m:= 1]
  
  dt[, `:=`(residual_a = detrended_a - seasonal_a, 
            residual_m = detrended_m / seasonal_m)]
  
  compare_ssacf(dt$residual_a, dt$residual_m)
}

seasonality_type_data = temp_data[, .(Type=seasonality_type(temp_data)),
                                  by = .(APMC, Commodity)]

write.csv(seasonality_type_data, "Seasonality_Type.csv")

## ----multiplicative_decomposition----------------------------------------
# Function for multiplicative decomposition
decomposition_m <- function(dt){
  dt[, trend := rollmean(modal_price, 12, fill="extend", align = "right")]
  dt[, `:=` (detrended_m = modal_price/trend)]
  dt[, `:=` (seasonal_m = mean(detrended_m, na.rm = TRUE)), by=.(Month)]
  dt[is.infinite(seasonal_m), seasonal_m:=1]
  
  dt[,`:=`(residual_m = detrended_m / seasonal_m)]
  return(dt)
}

decomposed_data = decomposition_m(temp_data)
decomposed_data$deseasonalised = decomposed_data$modal_price / decomposed_data$seasonal_m

write.csv(decomposed_data, "Deseasonalized_Data.csv")

## ----comparison_prices---------------------------------------------------
price_compare <- function (main_data, msp_data){
  main_data$raw_msp_comp = NA
  main_data$deseas_msp_comp = NA
  
  for (i in 1:nrow(main_data)){
    for (j in 1:nrow(msp_data)){
      if (main_data$Commodity[i] == msp_data$commodity[j]){
        if(main_data$modal_price[i] > msp_data$msprice[j]){
          main_data$raw_msp_comp[i] = "Above MSP"
        }
        else{
          main_data$raw_msp_comp[i] = "Below MSP"
        }
        
        if(main_data$deseasonalised[i] > msp_data$msprice[j]){
          main_data$deseas_msp_comp[i] = "Above MSP"
        }
        else {
          main_data$deseas_msp_comp[i] = "Below MSP"
        }
      }
    }
  }
  return (main_data)
}

# Subset data as MSP data is available for 2014 onwards
msp = subset(msp, year >= 2014)
msp = msp[!is.na(msp$msprice),]

a = filter(decomposed_data, Year == 2014)
b = filter(decomposed_data, Year == 2015)
c = filter(decomposed_data, Year == 2016)
d = filter(msp, year == 2014)
e = filter(msp, year == 2015)
f = filter(msp, year == 2016)

a = as.data.table(a); b = as.data.table(b); c = as.data.table(c)
d = as.data.table(d); e = as.data.table(e); f = as.data.table(f)

comparison_output = rbind(price_compare(a,d), price_compare(b,e), price_compare(c,f))
comparison_output = comparison_output[complete.cases(comparison_output), ]
write.csv(comparison_output, 'MSP_Comparison_(Raw_&_Deseasonalized).csv')

## ----summarizing_comparison----------------------------------------------
sum(comparison_output$deseas_msp_comp == 'Below MSP')
sum(comparison_output$deseas_msp_comp == 'Above MSP')

sum(comparison_output$raw_msp_comp == 'Below MSP')
sum(comparison_output$raw_msp_comp == 'Above MSP')

## ----echo=FALSE, message=FALSE, warning=FALSE----------------------------
analysis_data = subset(monthly_data_MSP, 
                       select = c("date", "APMC", "Commodity", 
                                  "district_name", "modal_price"))
analysis_data$date = as.Date(as.yearmon(analysis_data$date))
analysis_data = analysis_data[order(analysis_data$date),]
row.names(data) = NULL

# Group data by APMC and Commodity
analysis_data = analysis_data %>% group_by(APMC, Commodity)
# Remove groups with less than 12 observations
analysis_data = analysis_data %>% filter(n()>24)

n_groups(analysis_data) # Number of groups in analysis_data 
length(unique(monthly_data_MSP$APMC)) # Number of groups in monthly_data_MSP

## ----subsetting_data-----------------------------------------------------
sub_1 = subset(monthly_data_MSP, APMC %in% "Jalgaon" & Commodity %in% "bajri", na.rm=TRUE)
sub_2 = subset(monthly_data_MSP, APMC %in% "Dhule" & Commodity %in% "wheathusked", na.rm=TRUE)
sub_3 = subset(monthly_data_MSP, APMC %in% "Gangapur" & Commodity %in% "sorgumjawar", na.rm=TRUE)
sub_4 = subset(monthly_data_MSP, APMC %in% "Nagpur" & Commodity %in% "ricepaddyhus", na.rm=TRUE)

## ---- plotting_theme, echo=FALSE, results='hide'-------------------------
plot_theme <- theme(axis.text.x=element_blank(),
        legend.title = element_blank(),
        legend.text = element_text(size = 7, face = "bold"),
        axis.title.x = element_text(size = 8, face = "bold"),
        axis.title.y = element_text(size = 8, face = "bold"),
        axis.text = element_text(size = 8),
        plot.title = element_text(hjust = 0.5, size = 9, face = "bold"))

## ----time-series_plots, echo=FALSE, results='hide', fig.keep='all'-------
sub1_plot <- autoplot(as.ts(sub_1$modal_price),
     xlab="Time", ylab="Modal Price", main="Jalgaon Bajri Prices") + plot_theme

sub2_plot <- autoplot(as.ts(sub_2$modal_price),
     xlab="Time", ylab="Modal Price", main="Dhule Wheat-Husked Prices") + plot_theme

sub3_plot <- autoplot(as.ts(sub_3$modal_price),
     xlab="Time", ylab="Modal Price", main="Gangapur Sorgum-Jawar Prices") + plot_theme

sub4_plot <- autoplot(as.ts(sub_4$modal_price),
     xlab="Time", ylab="Modal Price", main="Nagpur RicePaddyHus Prices") + plot_theme

grid.arrange(sub1_plot, sub2_plot, 
             sub3_plot, sub4_plot, ncol=2)

## ----acf_plots, echo=FALSE, results='hide', fig.keep='all'---------------
acf_plotter <- function(acf_plot){
  library(ggplot2)
  x = with(acf_plot, data.frame(lag, acf))
  q = ggplot(data=x, mapping = aes(x=lag, y=acf)) +
        geom_hline(aes(yintercept = 0)) + 
        geom_segment(mapping = aes(xend=lag, yend=0))
  return(q)
}

g1 <- acf_plotter(acf(sub_1$modal_price, plot=FALSE)) + plot_theme
g2 <- acf_plotter(acf(sub_1$modal_price, plot=FALSE)) + plot_theme
g3 <- acf_plotter(acf(sub_1$modal_price, plot=FALSE)) + plot_theme
g4 <- acf_plotter(acf(sub_1$modal_price, plot=FALSE)) + plot_theme

grid.arrange(g1, g2, 
             g3, g4, ncol=2)

# Augmented Dicky-Fuller Test
print("ADF Test p-value for sub_1: ")
  adf.test(sub_1$modal_price)
print("ADF Test p-value for sub_2: ")
  adf.test(sub_2$modal_price)
print("ADF Test p-value for sub_3: ") 
  adf.test(sub_3$modal_price)
print("ADF Test p-value for sub_4: ") 
  adf.test(sub_4$modal_price)

## ---- time_series_decomposition, results='hide', fig.keep='all'----------
# Data preparation
monthly_data_MSP1 = merge(decomposed_data, msp, 
                              by.x=c("Commodity", "Year"),
                              by.y=c("commodity", "year"))

sub_1 = subset(monthly_data_MSP1, APMC %in% "Jalgaon" & Commodity %in% "bajri", na.rm=TRUE)
sub_2 = subset(monthly_data_MSP1, APMC %in% "Dhule" & Commodity %in% "wheathusked", na.rm=TRUE)
sub_3 = subset(monthly_data_MSP1, APMC %in% "Gangapur" & Commodity %in% "sorgumjawar", na.rm=TRUE)
sub_4 = subset(monthly_data_MSP1, APMC %in% "Nagpur" & Commodity %in% "ricepaddyhus", na.rm=TRUE)

c1 <- ggplot(sub_1, aes(x=date, group=1)) + 
  geom_line(aes(y=modal_price, colour="Raw Price")) + 
  geom_line(aes(y=msprice, colour="MSP")) + 
  geom_line(aes(y=deseasonalised, colour="Deseasonalised")) +
  plot_theme + labs(y="Prices", x="Date", title="Bajri Prices in Jalgaon")

c2 <- ggplot(sub_2, aes(x=date, group=1)) + 
  geom_line(aes(y=modal_price, colour="Raw Price")) + 
  geom_line(aes(y=msprice, colour="MSP")) + 
  geom_line(aes(y=deseasonalised, colour="Deseasonalised")) +
  plot_theme  + labs(y="Prices", x="Date", title="Wheat-Husked Prices in Dhule")

c3 <- ggplot(sub_3, aes(x=date, group=1)) + 
  geom_line(aes(y=modal_price, colour="Raw Price")) + 
  geom_line(aes(y=msprice, colour="MSP")) + 
  geom_line(aes(y=deseasonalised, colour="Deseasonalised")) +
  plot_theme + labs(y="Prices", x="Date", title="Sorgum-Jawar Prices in Gangapur")

c4 <- ggplot(sub_4, aes(x=date, group=1)) + 
  geom_line(aes(y=modal_price, colour="Raw Price")) + 
  geom_line(aes(y=msprice, colour="MSP")) + 
  geom_line(aes(y=deseasonalised, colour="Deseasonalised")) +
  plot_theme + labs(y="Prices", x="Date", title="RicyPaddyHus Prices in Nagpur")

ggarrange(c1, c2, c3, c4, 
          ncol=2, nrow=2, 
          common.legend = TRUE, legend="right")

## ---- flagging_AMPCC-----------------------------------------------------
monthly_data_MSP$fluctuation = monthly_data_MSP$max_price - monthly_data_MSP$min_price

# Filtering data by years
year_2014 = monthly_data_MSP %>% filter(Year == 2014)
year_2015 = monthly_data_MSP %>% filter(Year == 2015)
year_2016 = monthly_data_MSP %>% filter(Year == 2016)

# Finding max fluctuation for each month & year
set_14 = tapply(year_2014$fluctuation, year_2014$Month, max, na.rm=TRUE)
set_15 = tapply(year_2015$fluctuation, year_2015$Month, max, na.rm=TRUE)
set_16 = tapply(year_2016$fluctuation, year_2016$Month, max, na.rm=TRUE)

# Function to flag the set of AMPC and Commodities with highest fluctuation
flag_fluctuation <- function (year_data, set){
  z = NULL
  for(i in 1:nrow(year_data)){
    if(year_data$Month[i] == names(set[1]) && 
      year_data$fluctuation[i] == set[1]){
      z = year_data[i, ]
    }
  }
  
  for(i in 1:nrow(year_data)){
    for(j in 2:length(set)){
      if(year_data$Month[i] == names(set[j]) && 
         year_data$fluctuation[i] == set[j]){
        z = rbind(z, year_data[i, ])
      }
    }
  }
  return(z)
}

fluctuation_data = rbind(flag_fluctuation(year_2014, set_14), 
                         flag_fluctuation(year_2015, set_15), 
                         flag_fluctuation(year_2016, set_16)) %>% arrange(date)

write.csv(fluctuation_data, "Fluctuation_Data.csv")
print_table(head(fluctuation_data[order(-fluctuation_data$fluctuation),], 15))

