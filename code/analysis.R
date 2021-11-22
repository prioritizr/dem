# Initialization
## load packages
library(raster)
library(terra)
library(sf)
library(rappdirs)
library(gdalUtils)
library(wdman)
library(RSelenium)
library(archive)

## set variables
### set number of threads
n_threads <- max(1, parallel::detectCores() - 2)

### wait time for page loading
page_wait <- 2

### specify directories
data_dir <- normalizePath("data")

### change this to where you want to save the outputs
output_dir <- normalizePath("results")

# Preliminary processing
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
  path <- file.path(cache_dir, basename(x))
  if (!file.exists(path)) {
    curl::curl_download(url = x, destfile = path, quiet = TRUE)
  }
  TRUE
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

## merge data together
raw_elev_path <- tempfile(fileext = ".tif")
raw_elev_data <- gdalUtils::mosaic_rasters(
  gdalfile = dir(temp_dir, "^.*\\.bil$", full.names = TRUE),
  dst_dataset = raw_elev_path,
  separate = FALSE,
  output_Raster = FALSE,
  force_ot = "Int32",
  of = "GTiff",
  wo = paste0("NUM_THREADS=", n_threads),
  oo = paste0("NUM_THREADS=", n_threads),
  co = c(
    "COMPRESS=LZW",
    paste0("NUM_THREADS=", n_threads)
  ),
  verbose = TRUE
)

## import data
template_data <- get_world_template(dir = rappdirs::user_data_dir("aoh"))

## project data
elevation_data <- terra_gdal_project(
  x = elevation_data,
  y = template_data,
  n_threads = n_threads,
  filename = tempfile(fileext = ".tif"),
  datatype = "INT2S",
  verbose = TRUE
)

# Exports
## save raster to disk
## create file path
curr_path <- file.path(output_dir, "prep-elevation-100m.tif")
### save raster
terra::writeRaster(
  elevation_data, curr_path, overwrite = TRUE
)
## assert all files saved
assertthat::assert_that(file.exists(curr_path))

## upload data to GitHub
withr::with_dir(output_dir, {
  piggyback::pb_upload(
    file = "prep-elevation-100m.tif",
    repo = "prioritizr/aoh",
    tag = "data",
    overwrite = TRUE
  )
})
