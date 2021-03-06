# Tests for average count functions
library(testthat)
library(dplyr)

check_within = function(within, radius, from, to) {
  expect_equal(nrow(within), length(radius))
  expect_equal(names(within),
               c("radius", "from_count", "to_count",
                 "from_with", "within_mean"))
  expect_equal(within$from_count, from)
  expect_equal(within$to_count, to)
}

csd = sample_cell_seg_data %>% filter(Phenotype != 'other')
dst = distance_matrix(csd)

# Smoke test of count_within. Mostly checks that it doesn't barf and
# that the correct cells are selected.
test_that("count_within smoke test", {
  within15 = count_within(csd, 'CK+', 'CD8+', 15, dst=dst)
  check_within(within15, 15, 2257, 228)

  within30 = count_within(csd, 'CK+', 'CD8+', 30, dst=dst)
  check_within(within30, 30, 2257, 228)
  expect_gt(within30$within_mean, within15$within_mean)

  within15tumor = count_within(csd, 'CK+', 'CD8+', 15,
                                       'Tumor', dst=dst)
  check_within(within15tumor, 15, 2192, 51)

  within = count_within(csd, 'CK+',
                        c('CD8+', 'FoxP3+'), 15, 'Tumor', dst=dst)
  check_within(within, 15, 2192, 51+34)

  within = count_within(csd,
                        c('CD8+', 'FoxP3+'),
                        'CK+',  15, 'Tumor', dst=dst)
  check_within(within, 15, 51+34, 2192)
})

test_that('count_within works', {
  path = file.path('test_data',
              'FIHC4__0929309_HP_IM3_2_cell_seg_data.txt')
  d = read_cell_seg_data(path)
  counts = count_within(d, 'Helper T', 'Cytotoxic T', 40)
  expected = c(40, 15, 6, 8, 23/15)
  expect_equal(as.numeric(counts), expected)
})

test_that("count_within works with no data", {
  within = count_within(csd, 'other', 'CD8+', 15, dst=dst)
  check_within(within, 15, 0, 228)
  expect_equal(within$from_with, 0)
  expect_equal(within$within_mean, 0)

  within = count_within(csd, 'CK+', 'other', 15, dst=dst)
  check_within(within, 15, 2257, 0)
  expect_equal(within$from_with, 0)
  expect_equal(within$within_mean, 0)

  within = count_within(csd, 'other', 'other', 15, dst=dst)
  check_within(within, 15, 0, 0)
  expect_equal(within$from_with, 0)
  expect_equal(within$within_mean, 0)
})

test_that("count_within works with multiple radii", {
  within = count_within(csd, 'CK+', 'CD8+', c(15, 30), dst=dst)
  check_within(within, c(15, 30), c(2257, 2257), c(228, 228))

  within = count_within(csd, 'other', 'other', c(15, 30), dst=dst)
  check_within(within, c(15, 30), c(0, 0), c(0, 0))
  expect_equal(within$from_with, c(0, 0))
  expect_equal(within$within_mean, c(0, 0))
})

test_that("count_within errors with invalid radii", {
  expect_error(count_within(csd, 'CK+', 'CD8+', integer(0), dst),
               'length\\(radius\\)')
  expect_error(count_within(csd, 'CK+', 'CD8+', c(1, -1), dst),
               'radius > 0')
})

# Test error handling of count_within_batch
test_that("count_within_batch error checking works", {
  base_path = system.file("extdata", package = "phenoptr")
  pairs = c('CK+', 'CD68+')
  radius = 10
  expect_error(count_within_batch(base_path, pairs, radius), base_path)

  base_path = sample_cell_seg_folder()
  expect_error(count_within_batch(base_path, pairs='CK+', radius),
               'is.list\\(pairs\\)')
  expect_error(count_within_batch(base_path, pairs=list(), radius),
               'length\\(pairs\\)')
})

test_that('count_within_batch works', {
  # This is a bit slow but it seems worth doing, the data set is a bit
  # more robust than the toy test_data
  base_path = sample_cell_seg_folder()
  pairs = list(c('CK+', 'CD8+'),
               c('CK+', 'CD68+'),
               c('CK+ PDL1+', 'CD68+'))
  rules = list('CK+ PDL1+'=list('CK+', ~`Entire Cell PDL1 (Opal 520) Mean`>3))
  radius = c(10, 25)
  categories = c('Tumor', 'Stroma')
  counts = count_within_batch(base_path, pairs, radius, categories, rules) %>%
    dplyr::mutate(within_mean=round(within_mean, 4))

  expect_equal(dim(counts), c(12, 10))

  # Regression test; these values haven't been hand-checked
  expected = readr::read_csv(file.path('test_results', 'count_within.csv'),
                             col_types='cccccniiin') %>%
    dplyr::mutate(within_mean=round(within_mean, 4))
  expect_equal(counts, expected)
})
