% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/get.trait.data.R
\name{check.lists}
\alias{check.lists}
\title{Compares two lists}
\usage{
check.lists(x, y)
}
\arguments{
\item{x}{first list}

\item{y}{second list}
}
\value{
true if two list are the same
}
\description{
Check two lists. Identical does not work since one can be loaded
from the database and the other from a CSV file.
}
\author{
Rob Kooper
}
