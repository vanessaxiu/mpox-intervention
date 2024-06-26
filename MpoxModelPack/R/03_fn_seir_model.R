  #' @title fn_model
  #' @author: Fanyu Xiu, Carla Doyle, Jesse Knight
  #' @description Loads the model function 
  #' @param city model one city at a time: "mtl" = Montreal, "trt" = Toronto, "van" = Vancouver
  #' @param import_cases_city number of imported cases
  #' @param bbeta_city transmission probability per effective contact
  #' @param omega_city mixing parameters assortativity odds ratio scale
  #' @param sd_city mixing parameters standard deviation
  #' @param RR_H_city rate ratio of change in sexual partner numbers among GBM with > 7 sexual partners before 2022
  #' @param RR_L_city rate ratio of change in sexual partner numbers among GBM with <= 7 sexual partners before 2022
  #' @param gamma1_city 1/duration of effective infectious period
  #' @param period_city days from the first reported cases to the last modeled case
  #' @param TRACING 1: contact tracing and isolating GBM; 0: no contact tracing and isolation
  #' @param VACCINATING 1: vaccinating GBM with 1-dose Imvamune vaccines; 0: no vaccination
  #' @param cpp 1: use Rcpp; 0: use R
  #' @return output_t a list of cases (daily reported cases across time), time (days since first reported case), X (array of size in each compartment across time), inc (daily incidence across time)
  #' @rdname fn_model
  #' @export 
  fn_model <- function(city,
                       import_cases_city,
                       bbeta_city, 
                       omega_city, 
                       sd_city = 2,
                       RR_H_city, 
                       RR_L_city,
                       gamma1_city, 
                       period_city = 150,
                       TRACING = 1,
                       VACCINATING = 1,
                       cpp 
                       ){ 
    
    ## check if city data was loaded
    if(is.null(upsilon[[city]])){
      stop(paste(city, "data wasn't loaded"))
    }
      
    ## make city-specific parameters
    # int
    days_imported_city <- unname(days_imported[city])
    days_RR_city <- unname(days_RR[city])
    end_city <- unname(days_imported_city + period_city)
    niter_city <- (end_city - sstart) / ddt + 1;
    N_city <- N[[city]]

    # double
    report_frac_city <- report_frac[[city]]
    
    # NumericVector
    N_ash_city <- N_ash[[city]] # now array, to be converted into vector if use Rcpp
    c_ash_city <- c_ash[[city]] # now array, to be converted into vector if use Rcpp
    psi_t_city <- psi_t[[city]]
    upsilon_city <- unname(upsilon[[city]])
    vartheta_city <- vartheta[[city]]
    
    # NumericMatrix
    ### age-hiv
    mix_odds_ah_city <- mix_odds_ah[[city]] 
    ### sexual activity
    mix_odds_s_city  <- omega_city * dnorm(abs(outer(1:n_sa_cats, 1:n_sa_cats, `-`)), sd = sd_city) * sd_city
    
    # array
    ### initial prevalence in each compartment by {a,s,h}
    init_prev_city <- init_prev[[city]] 
    
    # pre-compute relative contact rates (array)
    RR_ash_city <- ifelse(c_ash_city > (7/180), 
                          RR_H_city, 
                          RR_L_city)
    
    ## import cases as per fraction of only certain age groups (based on case data)
    and <- which(names_age_cats %in% c("30-39"))
    ## in the 5% highest activity group
    ind <- unname(which(cumsum(apply(N_ash_city, 2, sum) / N_city) >= 0.95)) # apply(N_ash_city, 2, sum) is N_s_city
    
    ### import equally to I and E compartments
    for(comp in c("I", "E")){
      for(a in names_age_cats[and]){
        for(s in names_sa_cats[ind]){
          for(h in names_hiv_cats){
            ### divide by 2 since allocating the cases to E and I compartments equally
            init_prev_city[[comp]][a, s, h] <- import_cases_city / 2 * N_ash_city[a, s, h] / sum(N_ash_city[and, ind, ])
          }}}}
    ### S compartment initial population after case importation
    init_prev_city[["S"]] <- N_ash_city - init_prev_city[["I"]] - init_prev_city[["E"]]
    
    
 if(cpp){
   # if code in Rcpp, convert all arrays into vector/matrix
   c_ash_city <- as.data.frame.table(c_ash_city)
   colnames(c_ash_city) <- c("age", "sa", "hiv", "c_ash")
   N_ash_city <- as.data.frame.table(N_ash_city)
   colnames(N_ash_city) <- c("age", "sa", "hiv", "N_ash")
   RR_ash_city <- as.data.frame.table(RR_ash_city)
   colnames(RR_ash_city) <- c("age", "sa", "hiv", "RR_ash")
   mega_ash_city <- merge(c_ash_city, 
                       N_ash_city)
   mega_ash_city <- merge(mega_ash_city,
                       RR_ash_city)
   for(comp in names_comp){
     init_prev_city[[comp]] <- as.data.frame.table(init_prev_city[[comp]])
     colnames(init_prev_city[[comp]]) <- c("age", "sa", "hiv", comp)
     mega_ash_city <- merge(mega_ash_city, init_prev_city[[comp]])
     init_prev_city[[comp]] <- NULL
   }
   c_ash_city <- mega_ash_city$c_ash
   N_ash_city <- mega_ash_city$N_ash
   RR_ash_city <- mega_ash_city$RR_ash
   init_prev_city <- as.matrix(mega_ash_city[, names_comp])
   
   # import to global environment
   global_pars <- list(days_imported_city = days_imported_city,
                       days_RR_city = days_RR_city,
                       end_city = end_city,
                       niter_city = niter_city,
                       report_frac_city = report_frac_city,
                       N_city =  N_city,
                       RR_ash_city = RR_ash_city,
                       N_ash_city =  N_ash_city,
                       c_ash_city = c_ash_city,
                       psi_t_city =  psi_t_city,
                       upsilon_city = upsilon_city,
                       vartheta_city = vartheta_city,
                       mix_odds_ah_city = mix_odds_ah_city,
                       mix_odds_s_city = mix_odds_s_city,
                       init_prev_city = init_prev_city
     )
   invisible(lapply( 1:length( global_pars ), function( x )
       assign( as.character( names( global_pars )[ x ] ),
               global_pars[[ x ]], 
               envir = .GlobalEnv ) ) )
   
   # run model with rcpp using set of variable parameters
   output_t <- fn_model_cpp(bbeta_city = bbeta_city, 
                            omega_city = omega_city,
                            RR_H_city = RR_H_city,
                            RR_L_city = RR_L_city,
                            gamma1_city = gamma1_city,
                            TRACING = TRACING,
                            VACCINATING = VACCINATING)
   
   output_t$X <- array( output_t$X, 
                        dim = c( n_comp,
                                 niter_city,
                                 n_age_cats,
                                 n_sa_cats, 
                                 n_hiv_cats),
                        dimnames = list( names_comp,
                                         paste0("iter", 1:niter_city),
                                         names_age_cats, 
                                         names_sa_cats,
                                         names_hiv_cats))
      return(output_t)
 }else{
      ## time
      time <- seq(sstart,
                  end_city,
                  by = ddt)
      
      ## output matrix dimension names
      strata_name = list(names_comp,
                       paste0("iter", 1:niter_city), 
                       names_age_cats, 
                       names_sa_cats,
                       names_hiv_cats)
      
      ### mixing probability by {a,h,ap,hp} change with t
      mix_ah4p <- array(NA,
                        dim = c(n_age_cats, n_hiv_cats, n_age_cats, n_hiv_cats), 
                        dimnames = list(names_age_cats,
                                        names_hiv_cats,
                                        names_age_cats,
                                        names_hiv_cats))
      ### mixing *contacts per-person* by {a,s,h,ap,sp,hp} change with t
      mix_ash6c <- array(NA,
                         dim = c(n_age_cats, n_sa_cats, n_hiv_cats, n_age_cats, n_sa_cats, n_hiv_cats), 
                         dimnames = list(names_age_cats,
                                         names_sa_cats,
                                         names_hiv_cats,
                                         names_age_cats,
                                         names_sa_cats,
                                         names_hiv_cats))
      
      output_t <- rep(0, niter_city)
      inc_t = output_t
      
      ## assign initial values for each stratified compartment in output matrix
      X <- array(data = NA, 
               dim = c(n_comp, niter_city, n_age_cats, n_sa_cats, n_hiv_cats),
               dimnames = strata_name)
      for(comp in names_comp){
        for(a in names_age_cats){
          for(s in names_sa_cats){
            for(h in names_hiv_cats){
            ## recall that each compartment's initial pop is a list of array, and has dim n_age_cats *   n_sa_cats * n_hiv_cats
            X[comp, 1, a, s, h] <- init_prev_city[[comp]][a, s, h]
          }}}}
    
    # iterate model over time sequence (using Euler algorithm)
    for (t in 2:niter_city){
      ## extract % vaccinated people per time step depending on the day
      ## start from 0, corresponding to time_conti in PHAC case data
      day_index <- floor(ddt * (t - 1)) 
      max_day_data <- length(psi_t_city)
      psi_t <- ifelse(VACCINATING, 
                      ifelse(day_index >= max_day_data,
                             psi_t_city[max_day_data],
                             psi_t_city[day_index + 1]),
                      0)

      # extract % isolated people per time step depending on the day
      upsilon_t <- ifelse(TRACING,
                          upsilon_city[day_index + 1],
                          0)

      # contact relative rates
      ifelse(
        (day_index >= days_imported_city &
        day_index <= days_imported_city + days_RR_city),
        c_ash_city_t <- c_ash_city * RR_ash_city, 
        c_ash_city_t <- c_ash_city)

      # compute the time-varying mixing matrix
      n_ash_t <- N_ash_city - X["J", t-1, , , ]   # non-isolating pop by {a,s,h}
      x_ash_t <- n_ash_t * c_ash_city_t       # total contacts by {a,s,h}
      x_ah_t  <- c(apply(x_ash_t, c(1, 3), sum)) # total contacts by {a,h} only
      mix_ah2_rand <- outer(x_ah_t, x_ah_t) / sum(x_ah_t)   # random mixing by {a,h}
      # apply preferences by {a,h}
      mix_ah2 <- apply_mix_odds_cpp(mix_ah2_rand, mix_odds_ah_city) 
      
      mix_ah4p[,,,] <- mix_ah2 / rowSums(mix_ah2) # make probability & reshape (10,10) -> (5,2,5,2)
      
      for (a in names_age_cats){        # self age
        for (ap in names_age_cats){     # ptr  age
          for (h in names_hiv_cats){    # self hiv
            for (hp in names_hiv_cats){ # ptr  hiv
              x_s  <- x_ash_t[a,  ,h ] * mix_ah4p[a, h, ap,hp] # total contacts by {s} among {a,h}
              x_sp <- x_ash_t[ap, ,hp] * mix_ah4p[ap,hp,a, h ] # total contacts by {sp} among {ap,hp}
              mix_s2_rand <- outer(x_s, x_sp) / c(.5 * sum(x_s) + .5 * sum(x_sp)) # random mixing by {s,sp}
              
              mix_ash6c[a, ,h, ap, ,hp] <- apply_mix_odds_cpp(mix_s2_rand, 
                                                           mix_odds_s_city) / n_ash_t[a, ,h] # contacts * mixing per-person
              
              
              
            }}}}
      
      
      for (a in names_age_cats){
        for (s in names_sa_cats){
          for (h in names_hiv_cats){
            
            ### calculate lambda_t_ash
            prev_apsphp = X["I",t-1,,,] / n_ash_t
            lambda_t_ash <- bbeta_city * sum(mix_ash6c[a,s,h,,,] * prev_apsphp)

      # disease natural history compartments
      X["S", t, a, s, h] <- X["S", t - 1, a, s, h] - ddt * (lambda_t_ash + psi_t * vartheta_city[a] / sum(X["S", t - 1, a, , ])) * X["S", t - 1, a, s, h] 
      X["V", t, a, s, h] <- X["V", t - 1, a, s, h] + ddt * (psi_t * vartheta_city[a] * X["S", t - 1, a, s, h] / sum(X["S", t - 1, a, , ]) - iota * lambda_t_ash * X["V", t - 1, a, s, h])
      X["E", t, a, s, h] <- X["E", t - 1, a, s, h] + ddt * (lambda_t_ash * X["S", t - 1, a, s, h] + iota * lambda_t_ash * X["V", t - 1, a, s, h] - alpha * X["E", t - 1, a, s, h])
      X["I", t, a, s, h] <- X["I", t - 1, a, s, h] + ddt * ((1 - upsilon_t) * alpha * X["E", t - 1, a, s, h] - gamma1_city * X["I", t - 1, a, s, h])
      X["J", t, a, s, h] <- X["J", t - 1, a, s, h] + ddt * (upsilon_t * alpha * X["E", t - 1, a, s, h] - gamma2 * X["J", t - 1, a, s, h])
      X["R", t, a, s, h] <- X["R", t - 1, a, s, h] + ddt * (gamma1_city * X["I", t - 1, a, s, h] + gamma2 * X["J", t - 1, a, s, h])

      # cases that become infectious (symptomatic or not)
      X["CS", t, a, s, h] <-  X["CS", t - 1, a, s, h] + ddt * (alpha * X["E", t - 1, a, s, h] - report_delay * X["CS", t - 1, a, s, h]) 
      # cases that are reported
      X["CR", t, a, s, h] <-  X["CR", t - 1, a, s, h] + ddt * (report_frac_city * report_delay * X["CS", t - 1, a, s, h]) 
      
      ## incidence is calculated as what entered into the E compartment
      inc_t[t] <- inc_t[t] + lambda_t_ash * X["S", t, a, s, h] + iota * lambda_t_ash * X["V", t, a, s, h]
      
      # debug for negative compartment size
      if (any(X[, t, a, s, h] < 0)){ 
        print("negative compartment")
        return(list(city = city,
                    iteration = t, 
                    age = a,
                    sex_act_grp = s,
                    hiv = h,
                    N_1_ash = sum(X[, 1, a, s, h]), #### initial number of people in the stratum ash
                    N_t_ash = sum(X[, t, a, s, h]), #### number of people in the stratum ash at iteration t
                    X_t_ash = X[, 1:t, a, s, h]))
        break}
      
      # debug for close population
      if (abs(sum(X[names_comp[1:6], t, a, s, h]) - sum(X[names_comp[1:6], 1, a, s, h])) > 0.00001) { 
        print("leaky stratum")
        return(list(city = city,
                    iteration = t, 
                    age = a,
                    sex_act_grp = s,
                    hiv = h,
                    N_1_ash = sum(X[, 1, a, s, h]),
                    N_t_ash = sum(X[, t, a, s, h]),
                    X_t_ash = X[, 1:t, a, s, h]))
        break}
      
      } ### a
      } ### s
      } ### h

    output_t[t] <- sum(report_frac_city * report_delay * X["CS", t, , , ])

    } ### for iteration
    
    output_t <- list(cases = output_t,
                       time = time,
                       X = X,
                       inc = inc_t)
      
    return(output_t)
      
 } ### for else (modeling with R)
} ### for the model function