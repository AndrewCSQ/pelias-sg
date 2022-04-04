# clear the environment
rm(list = ls())

# load required libraries
# tidyverse for data handling
library(tidyverse)

# custom column specification os POSTAL is read as character
onemap_cols <- cols(
    X = "d",
    Y = "d",
    LATITUDE = "d",
    LONGITUDE = "d",
    .default = "c"
)

# Preparation procedure
# We construct
#   1. A venue-layer dataset with the name of the point of interest by BUILDING
#   2. An address-layer dataset with the blk_no + road_name
#   3. A postal code layer dataset using the postal code

# prepare LTA dataset
lta <- read_csv(
    "data/geocoded/lta-station-info-geo.csv",
    col_types = onemap_cols
    ) %>%
    # drop the longtitude column
    select(-LONGTITUDE)

lta_venue <- lta %>%
    # construct the name of the mrt
    # we use OneMap's searchval
    mutate(name = BUILDING) %>%
    # now construct aliases in english
    mutate(name_json = paste0('["',
        paste(stn_code, onemap_query, sep = '", "'),
        '"]')) %>%
    # construct aliases in chinese
    mutate(name_zh = if_else(str_detect(mrt_line_english, "LRT"),
        paste0(mrt_station_chinese, "轻轨"),
        paste0(mrt_station_chinese, "地铁"))) %>%
    # define a source column
    mutate(source = "onemap") %>%
    # layer is venue
    mutate(layer = "venue") %>%
    # rename lat and lon to pelias-friendly names
    rename(lon = LONGITUDE, lat = LATITUDE) %>%
    select(name, name_zh, name_json, source, layer, lat, lon)

# process mall list
mall <- read_csv("data/geocoded/mall-list-geo.csv", col_types = onemap_cols) %>%
    # drop LONGTITUDE
    select(-LONGTITUDE)

mall_venue <- mall %>%
    # set venue name to be the building field
    rename(name = BUILDING, lon = LONGITUDE, lat = LATITUDE) %>%
    # define a source column
    mutate(source = "onemap") %>%
    # layer is venue
    mutate(layer = "venue") %>%
    select(name, source, layer, lat, lon)

# process moe
moe <- read_csv("data/geocoded/moe-school-directory-geo.csv",
    col_types = onemap_cols) %>%
    # drop LONGTITUDE
    select(-LONGTITUDE)

moe_venue <- moe %>%
    # construct the name of the school
    rename(name = school_name) %>%
    # now construct aliases in english
    mutate(name_json = paste0('["',
        paste(BUILDING, sep = '", "'),
        '"]')) %>%
    # define a source column
    mutate(source = "onemap") %>%
    # layer is venue
    mutate(layer = "venue") %>%
    # rename lat and lon to pelias-friendly names
    rename(lon = LONGITUDE, lat = LATITUDE) %>%
    select(name, name_json, source, layer, lat, lon)

# address and postal code can be done all at once
onemap <- read_csv("data/geocoded/onemap-postal-dump.csv",
    # NIL is an NA too
    na = c("", "NA", "na", "NIL"),
    col_types = onemap_cols)

# generate the building names for onemap_venue
# retrieve the set of already mapped venues
dedupe_onemap_venue <- unique(c(lta$BUILDING, moe$BUILDING, mall$BUILDING))
onemap_venue <- onemap %>%
    # BUILDING must not be empty
    filter(!is.na(BUILDING)) %>%
    # filter for e.g. TEMPORARY SITE OFFICES etc.
    # we use some regex here where \\b means start of a word
    filter(!str_detect(BUILDING, "\\bTEMPORARY")) %>%
    # use building as name
    rename(name = BUILDING) %>%
    # define a source column
    mutate(source = "onemap") %>%
    # layer is venue
    mutate(layer = "venue") %>%
    # rename lat and lon to pelias-friendly names
    rename(lon = LONGITUDE, lat = LATITUDE) %>%
    select(name, source, layer, lat, lon) %>%
    # dedupe against other venue datasources
    filter(!(name %in% dedupe_onemap_venue))

all_address <- bind_rows(lta, mall, moe, onemap) %>%
    # address is BLK + ROAD_NAME
    mutate(name = paste(BLK_NO, ROAD_NAME)) %>%
    # define a source column
    mutate(source = "onemap") %>%
    # layer is venue
    mutate(layer = "address") %>%
    # rename lat and lon to pelias-friendly names
    rename(lon = LONGITUDE, lat = LATITUDE) %>%
    # have the address be an alias in case we search the building name
    # in the address layer
    # bracket the address so that pelias importer loads it properly
    mutate(ADDRESS = paste0("[", ADDRESS, "]")) %>%
    rename(name_json = ADDRESS) %>%
    select(name, name_json, source, layer, lat, lon) %>%
    distinct()

all_postal <- bind_rows(lta, mall, moe, onemap) %>%
    # address is BLK + ROAD_NAME
    mutate(name = POSTAL) %>%
    # define a source column
    mutate(source = "onemap") %>%
    # layer is venue
    mutate(layer = "postalcode") %>%
    # rename lat and lon to pelias-friendly names
    rename(lon = LONGITUDE, lat = LATITUDE) %>%
    select(name, source, layer, lat, lon) %>%
    distinct()

# write out all files
write_csv(lta_venue, "data/pelias/lta-venue.csv")
write_csv(moe_venue, "data/pelias/moe-venue.csv")
write_csv(mall_venue, "data/pelias/mall-venue.csv")
write_csv(onemap_venue, "data/pelias/onemap-venue.csv")
write_csv(all_address, "data/pelias/all-address.csv")
write_csv(all_postal, "data/pelias/all-postal.csv")
