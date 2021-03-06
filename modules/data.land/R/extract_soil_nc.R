#' Extract soil data
#'
#' @param in.file 
#' @param outdir 
#' @param lat 
#' @param lon 
#'
#' @return
#' @export
#'
#' @examples
#' in.file <- "~/paleon/env_paleon/soil/paleon_soil.nc"
#' outdir  <- "~/paleon/envTest"
#' lat     <- 40
#' lon     <- -80
#' \donotrun{
#'    PEcAn.data.land::extract_soil_nc(in.file,outdir,lat,lon)
#' }
extract_soil_nc <- function(in.file,outdir,lat,lon){
  
  ## open soils
  nc <- ncdf4::nc_open(in.file)
  
  ## extract lat/lon
  dims <- names(nc$dim)
  lat.dim <- dims[grep("^lat",dims)]
  lon.dim <- dims[grep("^lon",dims)]
  soil.lat <- ncdf4::ncvar_get(nc, lat.dim)
  soil.lon <- ncdf4::ncvar_get(nc, lon.dim)
  
  ## check in range
  dlat <- abs(median(diff(soil.lat)))
  dlon <- abs(median(diff(soil.lon)))
  if(lat < (min(soil.lat)-dlat) | lat > (max(soil.lat)+dlat)){
    PEcAn.utils::logger.error("site lat out of bounds",lat,range(soil.lat))
  }
  if(lon < (min(soil.lon)-dlon) | lon > (max(soil.lon)+dlon)){
    PEcAn.utils::logger.error("site lon out of bounds",lon,range(soil.lon))
  }
  if(dims[1] == lat.dim){
    soil.row <- which.min(abs(lat-soil.lat))
    soil.col <- which.min(abs(lon-soil.lon))
  } else if(dims[1] == lon.dim){
    soil.col <- which.min(abs(lat-soil.lat))
    soil.row <- which.min(abs(lon-soil.lon))
  } else {
    PEcAn.utils::logger.error("could not determine lat/lon dimension order:: ",dims)
  }
  
  ## extract raw soil data
  soil.data <- list()
  soil.vars <- names(nc$var)
  for(i in seq_along(soil.vars)){
    if(length(dims) == 2){
      soil.data[[soil.vars[i]]] <- ncdf4::ncvar_get(nc,soil.vars[i])[soil.row,soil.col]
    } else {
      ## assuming there's a 3rd dim of soil depth profile
      soil.data[[soil.vars[i]]] <- ncdf4::ncvar_get(nc,soil.vars[i])[soil.row,soil.col,]
    }
  }
  ncdf4::nc_close(nc)
  
  ## PalEON / MSTMIP / UNASM hack
  # t_ variables are topsoil layer (0– 30 cm) and
  # s_ variables are subsoil layer (30–100 cm)
  depth <- ncdf4::ncdim_def(name = "depth", units = "meters", vals = c(0.3,1.0), create_dimvar = TRUE)  
  dvars <- soil.vars[grep("t_",soil.vars,fixed=TRUE)]
  for(i in seq_along(dvars)){
    svar <- sub("t_","s_",dvars[i])
    soil.data[[dvars[i]]] <- c(soil.data[[dvars[i]]],soil.data[[svar]]) ## combine different depths
    soil.data[[svar]] <- NULL  ## drop old variable
    names(soil.data)[which(names(soil.data) == dvars[i])] <- sub("t_","",dvars[i]) ## rename original
  }
  
  
  ## name/unit conversions 
  soil.data$sand   <- soil.data$sand/100
  soil.data$silt   <- soil.data$silt/100
  soil.data$clay   <- soil.data$clay/100
  soil.data$oc     <- soil.data$oc/100
  soil.data$gravel <- soil.data$gravel/100
  soil.data$ref_bulk <- udunits2::ud.convert(soil.data$ref_bulk,"g cm-3","kg m-3")
  names(soil.data)[which(names(soil.data) == "clay")] <- "volume_fraction_of_clay_in_soil"
  names(soil.data)[which(names(soil.data) == "sand")] <- "volume_fraction_of_sand_in_soil"
  names(soil.data)[which(names(soil.data) == "silt")] <- "volume_fraction_of_silt_in_soil"
  names(soil.data)[which(names(soil.data) == "gravel")] <- "volume_fraction_of_gravel_in_soil"
  names(soil.data)[which(names(soil.data) == "ref_bulk")] <- "soil_bulk_density"
  names(soil.data)[which(names(soil.data) == "ph")]   <- "soil_ph"
  names(soil.data)[which(names(soil.data) == "cec")]  <- "soil_cec" ## units = meq/100g
  names(soil.data)[which(names(soil.data) == "oc")]   <- "soilC"  ## this is currently the BETY name, would like to change and make units SI
  
  ## convert soil type to parameters via look-up-table / equations
  mysoil <- PEcAn.data.land::soil_params(sand=soil.data$volume_fraction_of_sand_in_soil,
                                         silt=soil.data$volume_fraction_of_silt_in_soil,
                                         clay=soil.data$volume_fraction_of_clay_in_soil,
                                         bulk=soil.data$soil_bulk_density)
  
  ## Merge in new variables
  for(n in seq_along(mysoil)){
    if(!(names(mysoil)[n] %in% names(soil.data))){
      soil.data[[names(mysoil)[n]]] <- mysoil[[n]]
    }
  }
  
  ## Because netCDF is a pain for storing strings, convert named class to number
  ## conversion back can be done by load(system.file("data/soil_class.RData",package = "PEcAn.data.land"))
  ## and then soil.name[soil_n]
  soil.data$soil_type <- soil.data$soil_n
  soil.data$soil_n <- NULL
  
  ## open new file
  prefix <- tools::file_path_sans_ext(basename(in.file))
  new.file <- file.path(outdir,paste0(prefix,".nc"))

  ## create netCDF variables
  ncvar <- list()
  for(n in seq_along(soil.data)){
    varname <- names(soil.data)[n]
    if(length(soil.data[[n]])>1){
      ## if vector, save by depth
      ncvar[[n]] <- ncdf4::ncvar_def(name = varname, 
                              units = soil.units(varname), 
                              dim = depth)
    }else {
      ## else save as scalar
      ncvar[[n]] <- ncdf4::ncvar_def(name = varname, 
                              units = soil.units(varname), 
                              dim=list())
    }
  }
  
  ## create new file
  nc <- ncdf4::nc_create(new.file, vars = ncvar)
  
  ## add data
  for (i in seq_along(ncvar)) {
      ncdf4::ncvar_put(nc, ncvar[[i]], soil.data[[i]]) 
  }

  ncdf4::nc_close(nc)
  
  return(new.file)
  
}


#' Get standard units for a soil variable
#'
#' @param varname 
#'
#' @return
#' @export
#'
#' @examples
#' soil.units("soil_albedo")
soil.units <- function(varname){
  variables <- as.data.frame(matrix(c("soil_depth","m",
                                      "soil_cec","meq/100g",
                                      "volume_fraction_of_clay_in_soil","m3 m-3",
                                      "volume_fraction_of_sand_in_soil","m3 m-3",
                                      "volume_fraction_of_silt_in_soil","m3 m-3",
                                      "volume_fraction_of_gravel_in_soil","m3 m-3",
                                      "volume_fraction_of_water_in_soil_at_saturation","m3 m-3",
                                      "volume_fraction_of_water_in_soil_at_field_capacity","m3 m-3",
                                      "volume_fraction_of_condensed_water_in_dry_soil","m3 m-3",
                                      "volume_fraction_of_condensed_water_in_soil_at_wilting_point","m3 m-3",
                                      "soilC","percent",
                                      "soil_ph","1",
                                      "soil_bulk_density","kg m-3",
                                      "soil_type","string",
                                      "soil_hydraulic_b","1",
                                      "soil_water_potential_at_saturation","m",
                                      "soil_hydraulic_conductivity_at_saturation","m s-1",
                                      "thcond0","W m-1 K-1",
                                      "thcond1","W m-1 K-1",
                                      "thcond2","1",
                                      "thcond3","1",
                                      "soil_thermal_conductivity","W m-1 K-1", 
                                      "soil_thermal_conductivity_at_saturation","W m-1 K-1", 
                                      "soil_thermal_capacity","J kg-1 K-1",
                                      "soil_albedo","1"
                                      ),
                                    ncol=2,byrow = TRUE))
  colnames(variables) <- c('var','unit')
  
  unit = which(variables$var == varname)
  
  if(length(unit) == 0){
    return(NA)
  }else{
    unit = as.character(variables$unit[unit])
    return(unit)
  }
  
}
