# A Better Pelias Setup for Singapore

[Pelias](https://pelias.github.io/pelias/) is a modular open-source geocoder using Elasticsearch, easily deployable using Docker and Docker-compose.

This project is configured to download/prepare/build a complete Pelias installation for Singapore, based loosely around [the official Pelias Singapore project](https://github.com/pelias/docker/tree/master/projects/singapore). Enhancements:

- Using a Singapore-specific (as opposed to SG-Msia-Brunei) OSM extract from [BBBike](https://download.bbbike.org/osm/bbbike/Singapore/)
- Including road information from Singapore Land Authority's (SLA) [national mapline on GovTech's datamall](https://data.gov.sg/dataset/national-map-line) [TODO]
- Including geo-encoding information from SLA's [OneMap API](https://www.onemap.gov.sg/docs/#onemap-rest-apis) as a custom `.csv` dataset

In particular, we use the OneMap API to:

- Geo-encode [LTA's list of MRT/LRT stations in English and Chinese](https://datamall.lta.gov.sg/content/dam/datamall/datasets/PublicTransportRelated/Train_Station_Codes_and_Chinese_Names.zip)
- Geo-encode [the list of shopping malls from Wikipedia](https://en.wikipedia.org/wiki/List_of_shopping_malls_in_Singapore)
- Geo-encode [the list of schools provided by MOE on GovTech's datamall](https://data.gov.sg/dataset/school-directory-and-information)
- Retrieve a dump of available postal codes and geo-encoding information as in [this repo](https://github.com/xuancong84/singapore-address-heatmap)

## Usage

### Quick-Start

**Configuration**

Edit the `.env` file according to required configuration. If the Pelias service is meant to be persistent across reboots, the `DATA_DIR` environment variable should be changed.

**Copying Data Over**

The prepared data files for importing into pelias should be copied from `data/pelias` into the `$DATA_DIR/extra-data` specified by the `.env` configuration - see `pelias.json` for details.

**Setting up Pelias**

Follow the instructions [in the official Pelias repo](https://github.com/pelias/docker) for installing Pelias. For convenience, the `pelias` command and associated libraries have been copied into this repository. The minimum configuration required in order to run this project are [installing prerequisites](https://github.com/pelias/docker#prerequisites), [install the pelias command](https://github.com/pelias/docker#installing-the-pelias-command) and [configure the environment](https://github.com/pelias/docker#configure-environment).

To run a complete build, execute the following commands:

```bash
pelias compose pull
pelias elastic start
pelias elastic wait
pelias elastic create
pelias download all
pelias prepare all
pelias import all
pelias compose up
```

You can now make queries against your new Pelias build:

http://localhost:4000/v1/search?text=sentosa

### Updating LTA and GovTech Data

`scripts/update-data.R` provides a cross-platform way to update the list of MRT/LRT stations from LTA and school information from MOE. Run it from the root of this project directory.

### Updating the OneMap API scrape

`scripts/scrape-onemap.R` contains code to re-scrape the OneMap API for a geo-encoding of the LTA/GovTech/Wikipedia datasets, and to retrieve a new dump of all possible postal codes. The `data/logs/` folder contains a log of attempted and successful postal codes. `scripts/prepare-pelias.R` should then be run to prepare the new data for importing into Pelias.