#' Parse a vector of phenotype names
#'
#' This helper function takes a user-friendly list of single and
#' multiple phenotype names and converts it to a named list of phenotype
#' selectors for use with [phenoptr::select_rows]. By using `parse_phenotypes`
#' a user does not have to know the (somewhat inscrutable)
#' details of `select_rows`.
#'
#' @param ... Phenotypes to be decoded, or a list of same, optionally with names.
#' @return A named list of phenotype selectors for use with
#'   [phenoptr::select_rows].
#' @section Details:
#' Each phenotype must be either a single phenotype name (e.g. CD3+ or CD8-)
#' or two or more names separated by a slash (/) or comma (,).
#'
#' Phenotypes containing slashes are interpreted as requiring *all* of the
#' individual phenotypes. For example, "CD3+/CD8-" is a CD3+ cell which is
#' also CD8-.
#'
#' Phenotypes containing commas are interpreted as requiring *any* of the
#' individual phenotypes. For example, "CD68+,CD163+" is a cell which is
#' either CD68+ or CD163+ or both.
#'
#' Additionally,
#' a phenotype name without a + or - and containing
#' either "Total" or "All" will be
#' interpreted as meaning "All cells".
#' @importFrom magrittr %>%
#' @export
#' @examples
#' # Create selectors for
#' # - All CD3+ cells
#' # - CD3+/CD8+ double-positive cells
#' # - CD3+/CD8- single-positive cells
#' # - All cells regardless of phenotype
#' # - Macrophages, defined as either CD68+ OR CD163+
#' parse_phenotypes("CD3+", "CD3+/CD8+", "CD3+/CD8-",
#'                  "Total Cells", Macrophage="CD68+,CD163+")
#' @md
parse_phenotypes = function(...) {
  phenos = list(...)

  # Allow passing a single list
  if (length(phenos)==1 && is.list(phenos[[1]]))
    phenos = phenos[[1]]

  # Check for non-character parameters
  non_char = !purrr::map_lgl(phenos, is.character)
  if (any(non_char))
    stop('parse_phenotypes only works with text descriptions, not ',
         phenos[non_char])

  # Strip leading/trailing spaces preserving any names
  phenos = purrr::map(phenos, stringr::str_trim)

  # If no names were given, phenos will have names(pheno) == NULL
  # If any names were given, missing names will be ''
  # One way or another, get a named list.
  if (is.null(names(phenos))) names(phenos)=phenos else {
    no_names = names(phenos) == ''
    names(phenos)[no_names] = phenos[no_names]
  }

  # This does the basic decoding
  purrr::map(phenos, function(pheno) {
    if (rlang::is_formula(pheno))
      stop("parse_phenotypes does not support formula definitions.")

    # Multiple AND phenotypes become a list
    if (stringr::str_detect(pheno, '/')) {
      # Can't have comma and slash
      if (stringr::str_detect(pheno, ','))
        stop(paste("Phenotype selectors may not contain both '/' and '.':", pheno))
      as.list(split_and_trim(pheno, '/'))
    }

    # Multiple OR phenotypes become a character vector
    else if (stringr::str_detect(pheno, ',')) split_and_trim(pheno, ',')

    # Ends with +- and no '/' or ',' is a single phenotype
    else if (stringr::str_detect(pheno, '[+-]$')) pheno

    # Contains Total or All returns NA which signals "Select All"
    else if (stringr::str_detect(pheno, stringr::regex('Total|All', ignore_case=TRUE)))
      NA
    else stop(paste("Unrecognized phenotype selector:", pheno))
  }) %>%
    rlang::set_names(names(phenos))
}

#' Split a single string and trim whitespace from the results
#' @param str A single string.
#' @param pattern Pattern to split on.
#' @return A character vector of split components.
split_and_trim = function(str, pattern) {
  stopifnot(is.character(str), length(str)==1)
  stringr::str_trim(stringr::str_split(str, pattern)[[1]])
}

#' Flexibly select rows of a data frame.
#'
#' Select rows of a data frame based on phenotypes or other
#' expressions.
#'
#' `select_rows` implements a flexible mechanism for selecting cells (rows)
#' from a cell segmentation table. Cells may be selected by single or
#' multiple phenotype, by expression level, or combinations of both.
#'
#' See the tutorial
#' [Selecting cells within a cell segmentation table](https://perkinelmer.github.io/phenoptr/articles/selecting_cells.html)
#'for extensive documentation and examples.
#'
#' @param csd A data frame
#' @param sel May be a character vector, a one-sided formula, a list
#'   containing such or `NA`. A character vector is interpreted as
#'   the name(s) of one or
#'   more phenotypes and selects any matching phenotype. A formula is
#'   interpreted as an expression on the columns of `csd`.
#'   Multiple list items are joined with AND. `NA` is interpreted
#'   as "select all". It is convienent for lists of selection criteria.
#' @return A logical vector of length `nrow(csd)` which selects rows
#'   according to `sel`.
#' @export
#' @examples
#' csd <- sample_cell_seg_data
#'
#' # Select tumor cells with PDL1 expression > 3
#' selector <- list('CK+', ~`Entire Cell PDL1 (Opal 520) Mean`>3)
#' pdl1_pos_tumor <- csd[select_rows(csd, selector),]
#' range(pdl1_pos_tumor$`Entire Cell PDL1 (Opal 520) Mean`)
#'
#' # Select all T-cells. Note: Use c() to combine phenotypes, not list()
#' selector <- c('CD8+', 'FoxP3+')
#' tcells <- csd[select_rows(csd, selector),]
#' table(tcells$Phenotype)
#' @md
#' @seealso [parse_phenotypes] for a convenient way to create selectors
#' for most common phenotypes.
select_rows <- function(csd, sel) {
  stopifnot(is.data.frame(csd))

  # Evaluate a single phenotype in a per-marker file
  evaluate_per_marker = function(s) {
    if (!stringr::str_detect(s, '[+-]$'))
      stop(paste0(s, ' is not a valid per-marker phenotype name.'))
    column_name = paste('Phenotype', stringr::str_remove(s, '[+-]$'))
    if (!column_name %in% names(csd))
      stop(paste0("No '", column_name, "' column in data."))
    csd[[column_name]] == s
  }

  # Evaluate a single selector
  select_one = function(s) {
    if (length(s)==1 && is.na(s)) {
      # NA means select all
      rep(TRUE, nrow(csd))
    } else if (is.character(s)) {
      # Selector is one or more phenotype names,
      # look for match with phenotype column
      # Any match qualifies
      if ('Phenotype' %in% names(csd)) {
        csd[['Phenotype']] %in% s
      }
      else {
        # Phenotype per-marker has multiple columns
        col_selections = purrr::map(s, evaluate_per_marker)
        purrr::reduce(col_selections, `|`)
      }
    } else {
      # Selector is a function, evaluate it on csd
      lazyeval::f_eval(s, csd)
    }
  }

  # Everything is selected by default
  result = rep(TRUE, nrow(csd))
  if (!is.list(sel)) sel = list(sel)
  for (s in sel)
    result = result & select_one(s)
  result
}

# Helper function to normalize lists of selectors into named lists of selectors,
# so we can give names to the selected items.
normalize_selector = function(sel) {
  if (is.null(sel) || length(sel)==0)
    stop("Empty selector")

  stopifnot(is.list(sel))

  if (!is.null(names(sel)))
    return (sel)

  # Name a single selector
  name_item = function(s) {
    if (is.character(s))
      return (paste(s, collapse='|'))
    else if (lazyeval::is_formula(s))
      return (lazyeval::f_text(s))
    else if (is.list(s))
      return (paste(purrr::map_chr(s, name_item), collapse='&'))
    else
      stop('Unknown selector type')
  }

  names(sel) = purrr::map_chr(sel, name_item)
  sel
}

# Make rules that select phenotypes.
#
# Given a list of phenotype names and a (possibly empty) list of rules
# which create some or all of the phenotypes, return a complete list of
# rules.
# @param phenotypes A list or vector of phenotype names. Values may be
# existing phenotypes or compound phenotypes.
# @param existing_rules A named list of phenotype rules.
# @return A named list of rules containing one entry for each member
# of `phenotypes`.
make_phenotype_rules <- function (phenotypes, existing_rules=NULL) {
  if (is.null(existing_rules))
    existing_rules = list()
  else if (!is.list(existing_rules)
           ||(length(existing_rules)>0 && is.null(names(existing_rules))))
      stop("existing_rules must be a named list.")

  existing_names = names(existing_rules)
  extra_names = setdiff(existing_names, phenotypes)
  if (length(extra_names) > 0)
    stop("A rule was given for an unused phenotype: ",
         paste(extra_names, sep=', '))

  # The default rule is just the phenotype name itself.
  missing_names = setdiff(phenotypes, existing_names)
  new_rules = purrr::set_names(as.list(missing_names))

  c(existing_rules, new_rules)
}
