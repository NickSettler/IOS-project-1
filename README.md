# Covid 19 Data Analysis

This is a study project. Created by a student of the [Brno University of Technology](https://www.fit.vutbr.cz/en/) for the course Operating Systems in 2022.

Script corona is used for data processing and visualization. Data is taken from the [Ministry of Health of the Czech Republic](https://www.mzcr.cz) Covid-19 [data repository](https://onemocneni-aktualne.mzcr.cz/api/v2/covid-19).


## Script usage
```sh
Usage: ./corona [-h] [FILTERS] [COMMAND] [LOG [LOG2 [...]]
  -h      display this help and exit
  FILTERS are one or more of:
    -a DATETIME     use data after date
    -b DATETIME     use data before date
    -g GENDER       use data with gender [Z/M]
    -s WIDTH        set max histogram width
  COMMAND is one of:
    infected        count the number of infected people
    merge           merge some files to one
    gender          print statistics about infected people grouping by gender
    age             print statistics about infected people grouping by age
    daily           print statistics about infected people grouping by day
    monthly         print statistics about infected people grouping by month
    yearly          print statistics about infected people grouping by year
    countries       print statistics about infected people grouping by country
    districts       print statistics about infected people grouping by district
    regions         print statistics about infected people grouping by region
  LOG is one or more csv data files
    Data scheme:
      id                  unique identifier
      datum               date of the report. Format: YYYY-MM-DD
      vek                 age of the person
      pohlavi             gender of the person. Format: M / Z
      kraj_nuts_kod       region where the infection was discovered
      okres_lau_kod       district  where the infection was discovered
      nakaza_v_zahranici  whether the infection was reported in the foreign country [1] or not [0]
      nakaza_zeme_csu_kod country where the infection appeared (only for foreign infections)
      reportovano_khs     whether the infection was reported by the health service [1] or not [0]
```