#Loading libraries

install.packages("tidybayes")
library(tidyverse)
library(tidybayes)
library(rstan)
library(patchwork)
options(mc.cores = 4)

#Gaussian linear model of height
stan_program <- '
data {
  int<lower=1> n; // number of observations
  vector[n] height; // outcome
}
parameters {
  real mu;
  real<lower=0,upper=50> sigma;
}
model {
  height ~ normal(mu, sigma);
  sigma ~ uniform(0, 50);
  mu ~ normal(178, 20);
}
'
#Loading data
stan_data <- read.csv('~/rethinking2/data/Howell1.csv', sep = ';') %>%
  filter(age >= 18) %>%
  compose_data

#Fitting model
m4.1 <- stan(model_code = stan_program, data = stan_data)
m4.1


#Linear prediction
stan_program <- '
data {
  int<lower=1> n;
  real xbar;
  vector[n] height; //number of observations
  vector[n] weight;
}
parameters {
  real<lower=0,upper=50> sigma;
  real<lower=0> b;
  real a;
}
model {
  vector[n] mu;
  mu = a + b * (weight - xbar);
  height ~ normal(mu, sigma);
  a ~ normal(178, 20);
  b ~ lognormal(0, 1);
  sigma ~ uniform(0, 50);
}
'
#Adding xbar to stan_data
stan_data$xbar <- mean(stan_data$weight)

#Fitting model
m4.3 <- stan(model_code = stan_program, data = stan_data)
m4.3


#Curves from lines
stan_program <- '
data {
  int<lower=1> n;   // number of observations
  int<lower=1> K;   // number of coefficients (including intercept)
  vector[n] height;      // outcome
  matrix[n, K] X;   // regressors, design matrix
}
parameters {
  real<lower=0,upper=50> sigma;
  vector[K] b;
}
transformed parameters {
  vector[n] mu;
  mu = X * b;
}
model {
  height ~ normal(mu, sigma);
  b[1] ~ normal(178, 20);
  b[2] ~ lognormal(0, 1);
  if (K > 2) {
    for (i in 3:K) {
      b[i] ~ normal(0, 10);
      }
  }
  sigma ~ uniform(0, 50);
}
generated quantities {
  vector[n] muhat;
  for (i in 1:n) {
    muhat[i] = normal_rng(mu[i], sigma);
  }
}
'

dat <- read.csv('~/rethinking2/data/Howell1.csv', sep = ';') %>% 
  mutate(weight = as.vector(scale(weight)))
datpred <- data.frame(weight = seq(min(dat$weight), max(dat$weight), length.out = 100)) 

#compose data into a list
stan_data <- compose_data(dat) 

stan_data$X <- model.matrix(~weight, dat)
stan_data$K <- ncol(stan_data$X)

#model fit
m4.4 <- stan(model_code = stan_program, data = stan_data)
m4.4


###Polinomial model###
stan_data$X <- model.matrix(~weight + I(weight^2), dat)
stan_data$K <- ncol(stan_data$X)
m4.5 <- stan(model_code = stan_program, data = stan_data)
m4.5

stan_data$X <- model.matrix(~weight + I(weight^2) + I(weight^3), dat)
stan_data$K <- ncol(stan_data$X)
m4.6 <- stan(model_code = stan_program, data = stan_data)
m4.6

#Plot results
plot_predictions <- function(mod) {
  pred <- mod %>% 
    spread_draws(mu[i], muhat[i]) %>% 
    mean_qi %>% 
    mutate(Weight = stan_data$weight,
           Height = stan_data$height) %>% 
    arrange(Weight)
  ggplot(pred) +
    geom_ribbon(aes(Weight, ymin = muhat.lower, ymax = muhat.upper), alpha = .2) +
    geom_ribbon(aes(Weight, ymin = mu.lower, ymax = mu.upper), alpha = .2, fill = 'red') +
    geom_line(aes(Weight, mu)) +
    geom_point(aes(Weight, Height), shape = 1, color = 'dodgerblue4', alpha = .5) +
    ylab('Height')
}

p1 <- plot_predictions(m4.4) + ggtitle('Linear')
p2 <- plot_predictions(m4.5) + ggtitle('Quadratic')
p3 <- plot_predictions(m4.6) + ggtitle('Cubic')

# combine plots with the `patchwork` package
p1 + p2 + p3


###Linear regression with basis functions###
library(splines)
#Data preparation
dat <- read.csv('~/rethinking2/data/cherry_blossoms.csv', sep = ';') %>% 
  filter(!is.na(doy))
num_knots <- 15
knot_list <- quantile(dat$year, probs = seq(0, 1, length.out = num_knots))
B <- bs(dat$year,
        knot = knot_list[-c(1, num_knots)],
        degree = 3,
        intercept = TRUE)
class(B) <- 'matrix'

stan_data <- dat %>% compose_data(B = B, 
                                  k = ncol(B),
                                  w = rep(0, ncol(B)))

stan_program <- '
data {
    int n;
    int k;
    int doy[n];
    matrix[n, k] B;
}
parameters {
    real a;
    vector[k] w;
    real<lower=0> sigma;
}
transformed parameters {
    vector[n] mu;
    mu = a + B * w;
}
model {
    for (i in 1:n) {
        doy[i] ~ normal(mu[i], sigma);
    }
    a ~ normal(100, 10);
    w ~ normal(0, 10);
    sigma ~ exponential(1);
}
'
m4.7 <- stan(model_code = stan_program, data = stan_data)
m4.7

#Plot results
datplot <- m4.7 %>% 
  gather_draws(mu[i]) %>% 
  mean_qi
datplot$'Day in year' <- dat$doy
datplot$Year <- dat$year

ggplot(datplot, aes(Year, 'Day in year')) +
  geom_point(alpha = .4, color = 'blue') +
  geom_ribbon(aes(Year, .value, ymin = .lower, ymax = .upper), alpha = .2) +
  geom_line(aes(Year, .value))
