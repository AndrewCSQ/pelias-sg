# clear the environment
rm(list = ls())

# load required libraries
# data.table for faster binding of rows
library(data.table)
# for URL encoding
library(utils)
# for JSON interaction
library(jsonlite)
# for web interaction
library(httr)
# tidyverse makes data handling easier
library(tidyverse)
# multi-core querying to make things go faster
library(parallel)
# f-string interface for R
library(glue)
# logging with today's date
library(lubridate)

# set the number of cores to use in multi-core geo-encoding
# we use 4 here so that OneMap doesn't lock us out
nc <- 4

# onemap querying function
onemap_query <- function(query) {
    # URLEncode the query (e.g. convert space to %20)
    url <- glue("https://developers.onemap.sg/commonapi/search?searchVal={URLencode(query)}&returnGeom=Y&getAddrDetails=Y")
    # use a GET command on the URL
    # we use a try-catch and retry 5 times
    resp <- NA
    for (i in 1:5) {
        resp <- tryCatch({
            GET(url) %>%
                content(as = "text") %>%
                fromJSON(flatten = T)
        },
        error = function (cond) {
            Sys.sleep(5)
        })
        # check if resp is null
        if (!is.null(resp)) break
    }

    # if all tries failed, return an empty tibble
    if (is.null(resp)) return(tibble())
    # check if there are any results
    if (resp$found > 0) {
        # there are results - take the first one
        first_entry <- resp$results %>%
            # filter for postal codes that are not NIL
            filter(POSTAL != "NIL")
        return(first_entry)
    } else {
        # no results, return an empty tibble
        return(tibble())
    }
}
# wrap onemap querying function in a way helpful for geo-encoding
onemap_geo <- function(query) {
    # we only want to take the first slice
    onemap_query(query) %>%
        slice(1) %>%
        # and then register the onemap_query
        mutate(onemap_query = query)
}

# assume we need to scrape LTA station info
lta <- read.csv("data/originals/lta-station-info.csv",
    # encoding is utf-16 for chinese characters
    fileEncoding = "utf-16",
    # it's actually a tab separated file
    sep = "\t") %>%
    # convert to a dplyr tibble for easy handling
    tibble() %>%
    # create the query list
    # this will be <station name> <LRT/MRT>
    # depending on whether "LRT" is in mrt_line_english
    mutate(onemap_query = if_else(
        str_detect(mrt_line_english, "LRT"),
        paste(str_trim(mrt_station_english), "LRT"),
        paste(str_trim(mrt_station_english), "MRT")
    )) %>%
    # special case: 10-Mile Junction was closed in 2019
    # but it will live on in our hearts forever
    # also Junction 10 is right on it
    mutate(onemap_query = if_else(
        stn_code == "BP14",
        "Junction 10",
        onemap_query
    ))
# parallel geo-encode the lta onemap queries
lta_onemap <- mclapply(
    lta$onemap_query,
    onemap_geo,
    mc.cores = nc
) %>% bind_rows()
# now merge this back into the lta dataset
lta <- lta %>%
    left_join(lta_onemap, by = c("onemap_query")) %>%
    distinct()

# assume we need to scrape all MOE schools
moe <- read_csv("data/originals/moe-school-directory.csv") %>%
    # onemap query is school_name + address + postal code
    mutate(onemap_query = school_name) %>%
    # SOTA is a special case
    mutate(onemap_query = if_else(
        onemap_query == "SCHOOL OF THE ARTS, SINGAPORE",
        "SCHOOL OF THE ARTS",
        onemap_query
    ))
# parallel geo-encode the moe onemap queries
moe_onemap <- mclapply(
    moe$onemap_query,
    onemap_geo,
    mc.cores = nc
) %>% bind_rows()
# merge back into the MOE dataset
moe <- moe %>%
    left_join(moe_onemap, by = c("onemap_query")) %>%
    distinct()

# assume we need to scrape all Wikipedia-listed shopping malls
malls <- read_csv("data/originals/mall-list.csv")
# parallel geo-encode the malls
malls_onemap <- mclapply(
    malls$mall_name,
    onemap_geo,
    mc.cores = nc
) %>% bind_rows()
# merge back into the mall dataset
malls <- malls %>%
    left_join(malls_onemap, by = c("mall_name" = "onemap_query")) %>%
    distinct()

# record all the postal codes that have already been scraped
already_scraped <- c(malls$POSTAL, moe$POSTAL, lta$POSTAL)
# according to the deterministic datasets above
# run all the possible 6-digit postal codes
# and setdiff against already_scraped
queries <- str_pad(
    # based on previous scraping, no valid postal codes below 018000
    as.character(18000:999999),
    width = 6, side = "left",
    pad = "0"
) %>% setdiff(already_scraped)
# quick wrapper function to log the postal code dump attempts
onemap_wrapper <- function(s) {
    results <- onemap_query(s)
    # log the attempted postal code
    write(s, file = glue("logs/attempted-postal-{today()}.txt"), append = T)
    # if the tibble was not empty, log in successful
    if (nrow(results) > 0) write(s, file = glue("logs/successful-postal-{today()}.txt"), append = T)
    results
}
# now scrape away
onemap_dump <- mclapply(
    queries,
    onemap_wrapper,
    mc.cores = nc
)

onemap_dump_df <- rbindlist(onemap_dump)

# save all the datasets
write_csv(lta, "data/geocoded/lta-station-info-geo.csv")
write_csv(moe, "data/geocoded/moe-school-directory-geo.csv")
write_csv(malls, "data/geocoded/mall-list-geo.csv")
write_csv(onemap_dump_df, "data/geocoded/onemap-postal-dump.csv")
