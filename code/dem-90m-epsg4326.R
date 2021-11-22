# Initialization
## load packages
library(raster)
library(terra)
library(sf)
library(gdalUtils)
library(wdman)
library(RSelenium)
library(archive)
library(assertthat)

## set variables
### set number of threads
n_threads <- max(1, parallel::detectCores() - 2)

### wait time for page loading
page_wait <- 2

### specify directories
temp_dir <- file.path(getwd(), "dem-tmp")
data_dir <- normalizePath("data")
output_dir <- normalizePath("results")

# Preliminary processing
### create directory if needed
if (!file.exists(temp_dir)) {
  dir.create(temp_dir, showWarnings = FALSE, recursive = TRUE)
}

## find URLs to download data
pjs <- wdman::phantomjs(verbose = FALSE)
rd <- RSelenium::remoteDriver(port = 4567L, browserName = "phantomjs")
rd$open(silent = TRUE)
rd$maxWindowSize()
rd$navigate("https://www.earthenv.org/DEM")
Sys.sleep(page_wait) # wait for page to load
src <- xml2::read_html(rd$getPageSource()[[1]][[1]], encoding = "UTF-8")
el <- xml2::xml_find_all(xml2::xml_find_all(src, ".//map"), ".//area")
urls <- xml2::xml_attr(el, "href")

## clean up web driver
try(rd$close(), silent = TRUE)
try(rd$close(), silent = TRUE)
try(pjs$stop(), silent = TRUE)
try(pjs$stop(), silent = TRUE)

## fetch elevation data
elev_archive_paths <- plyr::laply(urls, .progress = "text", function(x) {
  path <- file.path(data_dir, basename(x))
  if (!file.exists(path)) {
    curl::curl_download(url = x, destfile = path, quiet = TRUE)
  }
  path
})

## unzip data
result <- plyr::laply(elev_archive_paths, .progress = "text", function(x) {
  d <- file.path(temp_dir, tools::file_path_sans_ext(basename(x)))
  if (!file.exists(d)) {
    dir.create(d, showWarnings = FALSE, recursive = TRUE)
  }
  archive_extract(archive = x, dir = d)
  TRUE
})

# Main processing
## merge data together
elev_path <- file.path(output_dir, "dem-90m-epsg4326.tif")
result <- gdalUtils::mosaic_rasters(
  gdalfile = dir(temp_dir, "^.*\\.bil$", recursive = TRUE, full.names = TRUE),
  dst_dataset = elev_path,
  separate = FALSE,
  output_Raster = FALSE,
  force_ot = "Int32",
  of = "GTiff",
  wo = paste0("NUM_THREADS=", n_threads),
  oo = paste0("NUM_THREADS=", n_threads),
  co = c(
    "COMPRESS=DEFLATE",
    paste0("NUM_THREADS=", n_threads),
    "BIGTIFF=YES"
  ),
  verbose = TRUE
)

## verify success
assertthat::assert_that(
  file.exists(elev_path),
  msg = "Oh no, something went wrong!"
)

# Clean up
if (!identical(temp_dir, tempdir())) {
  unlink(temp_dir, force = TRUE, recursive = TRUE)
}
