# Initialization
## load packages
library(raster)
library(terra)
library(sf)
library(gdalUtils)
library(assertthat)

## set variables
### specify directories
output_dir <- normalizePath("results")

### set number of threads
n_threads <- max(1, parallel::detectCores() - 2)

### set GDAL cache
cache_limit <- 5000

## define output crs
rast_crs <- sf::st_crs("ESRI:54017")

# Define helper functions
create_template_rast <- function(xres, yres, crs, bbox) {
  # assert arguments are valid
  assertthat::assert_that(
    assertthat::is.count(xres),
    assertthat::noNA(xres),
    assertthat::is.count(yres),
    assertthat::noNA(yres),
    inherits(crs, "crs"),
    inherits(bbox, "bbox")
  )
  # preliminary processing
  xmin <- floor(bbox$xmin[[1]])
  xmax <- xmin + (xres * ceiling((ceiling(bbox$xmax[[1]]) - xmin) / xres))
  ymin <- floor(bbox$ymin[[1]])
  ymax <- ymin + (yres * ceiling((ceiling(bbox$ymax[[1]]) - ymin) / yres))
  # create raster
  r <- terra::rast(
    xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax,
    nlyrs = 1,
    crs = as.character(crs)[[2]],
    resolution = c(xres, yres)
  )
  # return raster
  r
}

# Preliminary processing
## verify that 90m version exists
assertthat::assert_that(
  file.exists(file.path(output_dir, "dem-90m-epsg4326.tif")),
  msg = "can't find the 90m elevation raster"
)

## import EPSG:4326 version
r <- terra::rast(file.path(output_dir, "dem-90m-epsg4326.tif"))

## create global extent in CRS
rast_extent <- expand.grid(
  x = c(terra::xmin(r), terra::xmax(r)),
  y = c(terra::ymin(r), terra::ymax(r))
)
rast_extent$z <- runif(nrow(rast_extent))
rast_extent <- sf::st_as_sf(
  rast_extent, coords = c("x", "y"), crs = sf::st_crs(4326)
)
rast_extent <- sf::st_transform(rast_extent, rast_crs)
rast_extent <- sf::st_bbox(rast_extent)

## create template raster
x <- create_template_rast(
  xres = 100, yres = 100, crs = rast_crs, bbox = rast_extent
)

## clean up
rm(r)

# Main processing
### create wkt file for coordinate reference system
wkt_path <- tempfile(fileext = ".wkt")
writeLines(terra::crs(x), wkt_path)

## project raster
output_path <- file.path(output_dir, "dem-100m-esri54017.tif")
gdalUtils::gdalwarp(
  srcfile = file.path(output_dir, "dem-90m-epsg4326.tif"),
  dstfile = output_path,
  t_srs = wkt_path,
  te = c(terra::xmin(x), terra::ymin(x), terra::xmax(x), terra::ymax(x)),
  te_srs = wkt_path,
  tr = terra::res(x),
  r = "near",
  of = "GTiff",
  co = c(
    "COMPRESS=DEFLATE",
    paste0("NUM_THREADS=", n_threads),
    "INTERLEAVE=BAND",
    "TILED=YES",
    "BIGTIFF=YES"
  ),
  wm = as.character(cache_limit),
  multi = isTRUE(n_threads >= 2),
  wo = paste0("NUM_THREADS=", n_threads),
  oo = paste0("NUM_THREADS=", n_threads),
  doo = paste0("NUM_THREADS=", n_threads),
  ot = "Int16",
  dstnodata = 0,
  overwrite = TRUE,
  output_Raster = FALSE,
  verbose = TRUE,
  q = FALSE
)

## remove NA flag so that zeros are zeros (and not NA values)
system(paste0("gdal_edit.py ", output_path, " -unsetnodata"))

## verify success
assertthat::assert_that(
  file.exists(output_path),
  msg = "Oh no, something went wrong with GDAL processing!"
)

# Checks
output_data <- terra::rast(output_path)
assertthat::assert_that(
  terra::compareGeom(output_data, x, res = TRUE, stopiffalse = FALSE),
  msg = "Output raster has incorrect spatial properties"
)
