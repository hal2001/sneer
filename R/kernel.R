# Distance weighting functions. Used to convert distances to similarities, which
# are in turn converted to probabilities in probability-based embedding. These
# functions work on the squared distances.

# Utility Functions -------------------------------------------------------

# Finite Difference Gradient of Kernel
#
# Calculates the gradient of a similarity kernel by finite difference.
# Only intended for testing purposes.
#
# @param kernel A similarity kernel.
# @param d2m Matrix of squared distances.
# @param diff Step size to take in finite difference calculation.
# @return Gradient matrix.
kernel_gr_fd <- function(kernel, d2m, diff = 1e-4) {
  d2m_fwd <- d2m + diff
  fwd <- kernel$fn(kernel, d2m_fwd)

  d2m_back <- d2m - diff
  back <- kernel$fn(kernel, d2m_back)

  (fwd - back) / (2 * diff)
}

# Ensure the Kernel has the Correct Symmetry
#
# This function should be called when the parameters of a kernel (e.g.
# the beta parameter of the exponential) are changed from a scalar to
# a vector or (vice versa). Such a change may result in the symmetry of
# the kernel changing from asymmetric to symmetric (and vice versa again).
#
# @param kernel A similarity kernel.
# @return Kernel with the type attribute of the function correctly set for
# its parameters.
check_symmetry <- function(kernel) {
  if (!is.null(kernel$check_symmetry)) {
    kernel <- kernel$check_symmetry(kernel)
  }
  kernel
}

# TRUE if the kernel is asymmetric.
# (potentially of interest if you are forcing the output probabilities to be
# joint)
# see also is_joint_out_prob
is_asymmetric_kernel <- function(kernel) {
  attr(kernel$fn, "type") == "asymm"
}

# TRUE if the kernel is symmetric
is_symmetric_kernel <- function(kernel) {
  attr(kernel$fn, "type") == "symm"
}

# generic dispatch for making a kernel dynamic: should be called by a kernel
# during before_init
# See dsne.R and itsne.R for dynamic kernel code
make_kernel_dynamic <- function(method) {
  if (is.null(method$kernel$make_dynamic)) {
    stop("Kernel cannot be made dynamic")
  }
  method$kernel$make_dynamic(method)
}

# Forces kernel to be treated as asymmetric, even if it initially has uniform
# parameters. This is important for dynamic kernels which could start symmetric
# and become asymmetric during optimization and in doing so invalidate any
# simplified stiffness expressions.
set_kernel_asymmetric <- function(kernel) {
  attr(kernel$fn, "type") <- "asymm"
  kernel
}

# Weight Functions --------------------------------------------------------

# Exponential Weighted Similarity
#
# A similarity function for probability-based embedding.
#
# The weight matrix, \eqn{W} is generated from the squared distances matrix,
# \eqn{D^2}{D2} by:
#
# \deqn{W = e^{-\beta D^2}}{exp(-beta * D2)}
#
# @param d2m Matrix of squared distances.
# @param beta exponential (precision) parameter.
# @return Weight matrix.
# @family sneer weight functions
exp_weight <- function(d2m, beta = 1) {
  exp(-beta * d2m)
}
attr(exp_weight, "type") <- "symm"

# Exponential (Distance) Weighted Similarity
#
# A similarity function for probability-based embedding.
#
# Applies exponential weighting to the distances, rather than the square of
# the distances. Included so results can be compared with the implementation
# of t-SNE in the
# \href{https://cran.r-project.org/web/packages/tsne/index.html}{R tsne}
# package.
#
# The weight matrix, \eqn{W} is generated from the squared distances matrix,
# \eqn{D^2}{D2} by:
#
# \deqn{W = e^{-\beta \sqrt{D^2}}}{W = exp(-beta * sqrt(D2))}
#
# @param d2m Matrix of squared distances.
# @param beta Exponential precision.
# @return Weight matrix.
# @family sneer weight functions
#
sqrt_exp_weight <- function(d2m, beta = 1) {
  exp(-beta * sqrt(d2m))
}
attr(sqrt_exp_weight, "type") <- "symm"

# Student-t Distribution Similarity
#
# A similarity function for probability-based embedding.
#
# Applies weighting using the Student-t distribution with one degree of
# freedom. Used in t-SNE.
#
# Compared to the exponential weighting this has a much heavier tail.
# The weight matrix, \eqn{W} is generated from the squared distances matrix,
# \eqn{D^2}{D2} by:
# \deqn{W = \frac{1}{(1 + D^2)}}{W = 1/(1 + D2)}
#
# @param d2m Matrix of squared distances.
# @return Weight matrix.
# @family sneer weight functions
#
tdist_weight <- function(d2m) {
  1 / (1 + d2m)
}
attr(tdist_weight, "type") <- "symm"


# Heavy-Tailed Similarity
#
# A similarity function for probability-based embedding.
#
# Applies a "heavy-tailed" similarity function that represents
# a generalization of the similarity functions used in SNE and t-SNE. The
# heavy-tailedness is with respect to that of the exponential functon.
# The weight matrix, \eqn{W} is generated from the squared distances matrix,
# \eqn{D^2}{D2} by:
# \deqn{W  = [(\alpha \beta D^2) + 1]^{-\frac{1}{\alpha}}}{W = ((alpha * beta * D2) + 1) ^ (-1 / alpha)}
#
# \eqn{\alpha \to 0}{alpha approaches 0}, the weighting function becomes
# exponential, and behaves like \code{exp_weight}. At
# \eqn{\alpha = 1}{alpha = 1}, the weighting function is the t-distribution
# with one degree of freedom, \code{tdist_weight}. Intermediate
# values provide an intermediate degree of tail heaviness.
# The \eqn{\beta}{beta} parameter is equivalent to that in the
# \code{exp_weight} function. This is set to one in methods suchs as
# SSNE and t-SNE.
#
# @param d2m Matrix of squared distances.
# @param beta The precision of the function. Becomes equivalent to the
# precision in the Gaussian distribution of distances as \code{alpha}
# approaches zero.
# @param alpha Tail heaviness. Must be greater than zero.
# @return Weight matrix.
# @family sneer weight functions
#
# @references
# Yang, Z., King, I., Xu, Z., & Oja, E. (2009).
# Heavy-tailed symmetric stochastic neighbor embedding.
# In \emph{Advances in neural information processing systems} (pp. 2169-2177).
# @examples
# # make a matrix of squared distances
# d2m <- dist(matrix(rnorm(12), nrow = 3)) ^ 2
#
# # exponential weighting
# wm_exp <-   heavy_tail_weight(d2m, alpha = 1.5e-8)
#
# # t-distributed weighting
# wm_tdist <- heavy_tail_weight(d2m, alpha = 0.0)
#
# # exponential weighting with a non-standard beta value
# wm_expb2 <- heavy_tail_weight(d2m, alpha = 1.5e-8, beta = 2.0)
heavy_tail_weight <- function(d2m, beta = 1, alpha = 1.5e-8) {
  ((alpha * beta * d2m) + 1) ^ (-1 / alpha)
}
attr(heavy_tail_weight, "type") <- "symm"

# Step Weight
#
# A similarity function for probability-based embedding.
#
# This function returns a value of one for input data less than or equal to
# the beta parameter, and zero otherwise.
#
# Useful for emulating a k-nearest neighbor style of weighting, as favored by
# Yang and co-workers (see the publication list). Note that the value of beta
# of beta is clamped so that it can't be smaller than the smallest value in the
# input matrix. This is to stop the output weights all being zero, which
# results in a uniform probability and hence a large perplexity. This can
# cause problems for the bisection search used to find the target perplexity.
#
# @param d2m Matrix of squared distances.
# @param beta step cutoff parameter.
# @return Weight matrix.
# @family sneer weight functions
#
#
# @references
# Yang, Z., Peltonen, J., & Kaski, S. (2014).
# Optimization equivalence of divergences improves neighbor embedding.
# In \emph{Proceedings of the 31st International Conference on Machine Learning (ICML-14)}
# (pp. 460-468).
#
# Yang, Z., Peltonen, J., & Kaski, S. (2015).
# Majorization-Minimization for Manifold Embedding.
# In \emph{AISTATS}.
step_weight <- function(d2m, beta = 1) {
  # beta is not allowed to be smaller than the smallest value in the distance
  # matrix
  (d2m <= max(beta, min(d2m))) * 1
}

# Exponential Kernel ------------------------------------------------------

# Exponential Kernel Factory Function
#
# Similarity Kernel factory function.
#
# Creates a list implementing the exponential kernel function and gradient.
#
# @param beta Exponential parameter.
# @return Exponential function and gradient.
# @family sneer similiarity kernels
#
exp_kernel <- function(beta = 1) {
  fn <- function(kernel, d2m) {
    exp_weight(d2m, beta = kernel$beta)
  }

  kernel <- list(
    fn = fn,
    gr = function(kernel, d2m) {
      exp_gr(d2m, beta = kernel$beta)
    },
    check_symmetry = function(kernel) {
      if (length(kernel$beta) > 1) {
        attr(kernel$fn, "type") <- "asymm"
      }
      else {
        attr(kernel$fn, "type") <- "symm"
      }
      kernel
    },
    beta = beta,
    name = "exp",
    make_dynamic = dynamize_exp_kernel
  )
  check_symmetry(kernel)
}

# Exponential Gradient
#
# Similarity Kernel Gradient.
#
# Calculates the gradient of the exponential function with respect to d2m,
# the matrix of squared distances.
#
# @param d2m Matrix of squared distances.
# @param beta exponential parameter.
# @return Matrix containing the gradient of (with respect to \code{d2m}).
exp_gr <- function(d2m, beta = 1) {
  -beta * exp_weight(d2m, beta = beta)
}


# Cauchy Kernel -----------------------------------------------------------

# t-Distribution Kernel Factory Function
#
# Similarity Kernel factory function.
#
# Creates a list implementing the t-distributed kernel function and gradient.
#
# @return t-Distributed function and gradient.
# @family sneer similiarity kernels
#
tdist_kernel <- function() {
  fn <- function(kernel, d2m) {
    tdist_weight(d2m)
  }
  attr(fn, "type") <- attr(tdist_weight, "type")

  list(
    fn = fn,
    gr = function(kernel, d2m) {
      tdist_gr(d2m)
    },
    name = "tdist"
  )
}

# Exponential Gradient
#
# t-Distributed Kernel Gradient.
#
# Calculates the gradient of the Student-t distribution with one degree of
# freedom with respect to d2m, the matrix of squared distances.
#
# @param d2m Matrix of squared distances.
# @return Matrix containing the gradient (with respect to \code{d2m}).
tdist_gr <- function(d2m) {
  -(tdist_weight(d2m) ^ 2)
}


# Heavy-Tail Kernel -------------------------------------------------------

# Heavy Tailed Kernel Factory Function
#
# Similarity Kernel factory function.
#
# Creates a list implementing a heavy tailed (compared to an exponential)
# function and gradient.
#
# @param beta Decay constant of the function. Becomes equivalent to the
# exponential decay constant a \code{alpha} approaches zero. The larger the
# value, the faster the function decays.
# @param alpha Tail heaviness. Must be greater than zero.
# @return Heavy tailed function and gradient.
# @family sneer similiarity kernels
#
heavy_tail_kernel <- function(beta = 1, alpha = 0) {
  fn <- function(kernel, d2m) {
    heavy_tail_weight(d2m, beta = kernel$beta, alpha = kernel$alpha)
  }

  kernel <- list(
    fn = fn,
    gr = function(kernel, d2m) {
      heavy_tail_gr(d2m, beta = kernel$beta, alpha = kernel$alpha)
    },
    beta = beta,
    alpha = clamp(alpha, sqrt(.Machine$double.eps)),
    check_symmetry = function(kernel) {
      if (length(kernel$beta) > 1 || length(kernel$alpha) > 1) {
        attr(kernel$fn, "type") <- "asymm"
      }
      else {
        attr(kernel$fn, "type") <- "symm"
      }
      kernel
    },
    name = "heavy",
    make_dynamic = dynamize_heavy_tail_kernel
  )
  kernel <- check_symmetry(kernel)
  kernel
}



# Heavy Tail Kernel Gradient.
#
# Calculates the gradient of the Student-t distribution with one degree of
# freedom with respect to d2m, the matrix of squared distances.
#
# @param d2m Matrix of squared distances.
# @param beta The precision of the function. Becomes equivalent to the
# precision in the Gaussian distribution of distances as \code{alpha}
# approaches zero.
# @param alpha Tail heaviness. Must be greater than zero.
# @return Matrix containing the gradient (with respect to \code{d2m}).
heavy_tail_gr <- function(d2m, beta = 1, alpha = 1.5e-8) {
  -beta * heavy_tail_weight(d2m, beta = beta, alpha = alpha) ^ (alpha + 1)
}

# Inhomogeneous Kernel ----------------------------------------------------


itsne_weight <- function(d2m, dof = 1) {
  (1 + d2m / dof) ^ (-0.5 * (dof + 1))
}
attr(itsne_weight, "type") <- "asymm"

itsne_gr <- function(d2m, dof = 1) {
  -(0.5 * (dof + 1) / (d2m + dof)) * itsne_weight(d2m, dof)
}

itsne_kernel <- function(dof = 1) {
  fn <- function(kernel, d2m) {
    itsne_weight(d2m, dof = kernel$dof)
  }

  kernel <- list(
    fn = fn,
    gr = function(kernel, d2m) {
      itsne_gr(d2m, dof = kernel$dof)
    },
    dof = dof,
    check_symmetry = function(kernel) {
      if (length(kernel$dof) > 1) {
        attr(kernel$fn, "type") <- "asymm"
      }
      else {
        attr(kernel$fn, "type") <- "symm"
      }
      kernel
    },
    name = "inhomogeneous",
    make_dynamic = dynamize_inhomogeneous_kernel
  )
  kernel <- check_symmetry(kernel)
  kernel
}

identity_weight <- function(d2m) {
  d2m
}
attr(identity_weight, "type") <- "symm"

no_kernel <- function() {
  fn <- function(kernel, d2m) {
    identity_weight(d2m)
  }
  attr(fn, "type") <- "symm"

  list(
    fn = fn,
    gr = function(kernel, d2m) {
      1
    },
    name = "none"
  )
}
