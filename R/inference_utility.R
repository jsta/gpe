# inference_utility

# create a posterior object (doesn't actually do much ...)
createPosterior <- function (inference_name,
                             lZ,
                             data,
                             kernel,
                             likelihood,
                             mean_function,
                             inducing_data,
                             weights,
                             ...) {
  # A posterior object must have the named arguments,
  # but may also contain method-specific things via the dots argument.
  # These will be combined into the element 'components'
  # need to check some things
  
  # combine these things into a single posterior object
  ans <- list(inference_name = inference_name,
              lZ = lZ,
              data = data,
              kernel = kernel,
              likelihood = likelihood,
              mean_function = mean_function,
              inducing_data = inducing_data,
              weights = weights,
              components = list(...))
  
  # set it to a posterior class
  class(ans) <- 'posterior'
  
  return (ans)
  
}

# safe Cholesky factorisation
jitchol <- function (A, maxtries = 5, verbose = TRUE) {
  # attempt to find the cholesky decomposition, and add 'jitter'
  # (a small amount of variance) to the diagonal maxtries times to try and
  # make it positive-definite
  L <- tryCatch(chol(A),
                error = function(x) return(NULL))
  
  if (is.null(L)) {
    
    # first check whether there are any negative elements
    if (any(diag(A) < 0)) {
      stop ('A Cholesky factorisation could not be found as the matrix is not positive-definite - it has negative diagonal elements')
    }
    
    # otherwise try adding jitter to the diagonal
    
    # get jitter as a fraction of the diagonal mean
    jitter <- mean(diag(A)) * 1e-6
    
    attempt <- 0
    while(is.null(L) & attempt <= maxtries) {
      # increment the counter
      attempt <- attempt + 1
      # increase the jitter
      jitter <- jitter * 10
      L <- tryCatch(chol(A + diag(nrow(A)) * jitter),
                    error = function(x) return(NULL))
    }
    
    # check whether L is a matrix (is not, it must be NULL)
    if (is.matrix(L)) {
      
      if (verbose) {
        # if a matrix was returned, and the user wants verbosity,
        # issue a warning
        warning (paste0('A Cholesky factorisation could not initially be computed, so ',
                        prettyNum(jitter),
                        ' was added to the diagonal.'))
      }
      
    } else {
      
      # otherwise throw an error
      stop (paste0('A Cholesky factorisation could not be computed, even after adding ',
                   prettyNum(jitter),
                   ' to the diagonal.'))
    }
    
  }
  
  # return the factorisation
  return (L)
  
}


getU <- function (x,
                  n = pmin(length(x), 100),
                  method = c('kmeans')) {
  
  # find the method required
  method <- match.arg(method)
  
  # if kmeans
  if (method == 'kmeans') {
    # get the cluster centres
    u <- kmeans(x, n)$centers
    # remove any names
    rownames(u) <- NULL
  }
  # return the inducing points
  return (u)
}

laplace_psi <- function(a, f, mn, y, d0, wt) {
  # $\psi$ (after Rasmussen & Williams) objective function for
  # Laplace approximation using newton iteration
  ans <- 0.5 * t(a) %*% (f - mn) - sum(d0(y, f, wt))
  dim(ans) <- NULL
  return (ans)
}

laplace_psiline_fitc <- function(s, adiff, a, Lambda_diag, B, y, d0, mn, wt) {
  # calculate psi for a given value of s (step size of the Newton iterations)
  # under an FITC GP
  a <- a + s * as.vector(adiff)
  # split this bit out into projection function
  f <- Lambda_diag * a + t(B) %*% (B %*% a) + mn
  laplace_psi(a, f, mn, y, d0, wt)
}

laplace_psiline_full <- function(s, adiff, a, K, y, d0, mn, wt) {
  # calculate psi for a given value of s (step size of the Newton iterations)
  # under an direct (non-sparse) GP
  a <- a + s * as.vector(adiff)
  f <- K %*% a + mn
  laplace_psi(a, f, mn, y, d0, wt)
}


# return an inference function, given an inference method and a family
getInference <- function (inference, likelihood, inducing_data) {
  
  # if inference is default, look up the default for that likelihood
  if (inference == 'default') {
    inference <- defaultInference(likelihood)
  }
  
  # check inference method is suitable for the likelihood
  checkInference(inference, likelihood, inducing_data)
  
  # get the inference name
  inference_name <- switch(inference,
                           FITC = 'direct_fitc',
                           full = 'direct_full',
                           LaplaceFITC = 'laplace_fitc',
                           Laplace = 'laplace_full')
  
  # if the inference method wasn't found throw an error
  if (is.null(inference_name)) {
    stop (paste0('Inference method ',
                 inference,
                 ' not found.'))
  }
  
  # prepend 'inference' to the name
  inference_name <- paste0('inference_',
                           inference_name)
  
  # fetch the function
  inference <- get(inference_name)
  
  # return this function
  return (inference)
  
}

getInferenceType <- function (inference_name) {
  # get the short name for an inference method from the function name
  
  # strip the inference bit off
  inference_split <- strsplit(inference_name, split = '_')[[1]]
  inference_name <- paste0(inference_split[-1], collapse = '_')
  
  # get the inference name
  inference_type <- switch(inference_name,
                           direct_fitc = 'FITC',
                           direct_full = 'full',
                           laplace_fitc = 'LaplaceFITC',
                           laplace_full = 'Laplace')
  
  # return it
  return (inference_type)
  
}

defaultInference <- function (likelihood) {
  
  inference <- switch(likelihood$name,
                      likelihood_gaussian_identity = 'full',
                      likelihood_binomial_logit = 'Laplace',
                      likelihood_binomial_probit = 'Laplace',
                      likelihood_poisson_log = 'Laplace')
  
  # if nothing found, throw an error
  if (is.null(inference)) {
    stop (paste0('no default inference method found for likelihood ',
                 likelihood$name))
  }
  
  return (inference)
  
}


checkInference <- function (inference, likelihood, inducing_data) {
  
  if (inference %in% c('full', 'FITC') &
        likelihood$name != 'likelihood_gaussian_identity') {
    stop ('full and FITC inference are only possible with the gaussian family and identity link')
  }
  
  if (inference %in% c('FITC', 'LaplaceFITC') &
        is.null(inducing_data)) {
    stop ('If FITC inference is required, inducing_data must be provided.')
  }
  
}

updateModel <- function (model,
                         response = NULL,
                         kernel = NULL,
                         data = NULL,
                         family = NULL,
                         mean_function = NULL,
                         inducing_data = NULL,
                         inference = NULL,
                         hyperinference = NULL,
                         verbose = NULL) {
  
  # take a fitted model object, update some of its components
  # (data, kernel, inducing points, inference method etc.) and refit
  
  # set up defaults
  if (is.null(response)) {
    response <- model$data$response
  }
  if (is.null(kernel)) {
    kernel <- model$kernel
  }
  if (is.null(data)) {
    data <- model$data$training_data
  }
  if (is.null(family)) {
    family <- getFamily(model$likelihood)
  }
  if (is.null(mean_function)) {
    mean_function <- model$mean_function
  }
  if (is.null(inducing_data)) {
    inducing_data <- model$data$inducing_data
  }
  if (is.null(inference)) {
    inference <- getInferenceType(model$posterior$inference_name)
  }
  if (is.null(hyperinference)) {
    hyperinference <- model$hyperinference
  }
  if (is.null(verbose)) {
    verbose <- model$verbose
  }
  
  # fit new model
  new_model <- gp(formula = response ~ kernel,
                  data = data,
                  family = family,
                  mean_function = mean_function,
                  inducing_data = inducing_data,
                  inference = inference,
                  hyperinference = hyperinference,
                  verbose = verbose)
  
  return (new_model)
  
}
