all: dem

dem: results/dem-90m-epsg4326.tif results/dem-100m-esri54017.tif

results/dem-90m-epsg4326.tif:
	R CMD BATCH --no-restore --no-save code/dem-90m-epsg4326.tif.R

results/dem-100m-esri54017.tif:
	R CMD BATCH --no-restore --no-save code/dem-100m-esri54017.R

clean:
	rm -f results/dem-90m-epsg4326.tif
	rm -f results/dem-100m-esri54017.tif

readme:
	R --slave -e "rmarkdown::render('README.Rmd')"

.PHONY: all dem readme
