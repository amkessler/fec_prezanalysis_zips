#first we'll run script step 00 to connect to db
source("00_connecttodb.R")

library(tidyverse)
library(lubridate)
library(janitor)
library(dbplyr)

#list the tables in the database
src_dbi(con)

#pull in the saved VIEW created from Alex's sql statement
zips <- tbl(con, "zips_by_prezcand")

glimpse(zips)

#save locally as a dataframe
zips_by_prezcands <- zips %>% 
  collect()

#any missing zips?
zips_by_prezcands %>% 
  filter(is.na(contributor_zip5))

#any repeated zips?
zips_by_prezcands %>% 
  count(pres_cand, contributor_zip5) %>% 
  filter(n > 1)

#example of repeated zip?
zips_by_prezcands %>% 
  filter(pres_cand == "Booker, Cory A.",
         contributor_zip5 == "00907")


#### BRING IN ZIP CODE LOOKUP TABLE #####

## we'll add named location associated with each zip code

ziplookup_raw <- read_csv("zip-codes-database-STANDARD.csv", 
                          col_types = cols(StateFIPS = col_character()))

# keep only one distinct record per zip code
ziplookup <- ziplookup_raw %>% 
  clean_names() %>% 
  select(zip_code, city, state, county, state_fips, county_fips, latitude, longitude) %>% 
  distinct(zip_code, .keep_all = TRUE) 

#any repeated zips?
ziplookup %>% 
  count(zip_code, state) %>% 
  filter(n > 1)

ziplookup %>% 
  filter(zip_code == "01062") 


# join 
joined <- left_join(contribs_by_zip, ziplookup, by = c("zip5" = "zip_code"))

#create column for just last name of candidate
joined$lastname <- str_split(joined$name, ",", simplify = TRUE)[,1]

#final table
byzip_bycand <- joined %>% 
  ungroup %>% 
  select(lastname, everything(), -name) %>% 
  mutate(fips = paste0(state_fips, county_fips)) 

byzip_bycand

#write to file
write_csv(byzip_bycand, "output/byzip_bycand.csv")



#### TOP 10 ZIPS FOR EACH CANDIDATE ####

#group by zip
top10_byzip_bycand <- byzip_bycand %>% 
  group_by(lastname) %>% 
  top_n(n = 10, wt = sumcontribs) %>% #pulls top 10 by sumcontribs value
  ungroup()

top10_byzip_bycand

#write to file
write_csv(top10_byzip_bycand, "output/top10_byzip_bycand.csv")

#any common zips?
top10_byzip_bycand %>% 
  count(zip5, city) %>% 
  arrange(desc(n))
  


# reshape to wide format as an alternative table structure ####
test <- byzip_bycand %>% 
  select(lastname, zip5, sumcontribs)

test_wide <- test %>% 
  spread(lastname, sumcontribs)

byzip_bycand_wide <- test_wide

#write to file
write_csv(byzip_bycand_wide, "output/byzip_bycand_wide.csv")



#### CALCULATING COUNTY-LEVEL TOTALS BASED ON ZIPS ####
## For Magic Wall

#start with existing zip breakdowns
byzip_bycand

#group by candidate, county
bycounty_bycand <- byzip_bycand %>% 
  filter(!is.na(county)) %>% 
  group_by(lastname, fips, county, state) %>% 
  summarise(sum_in_county = sum(sumcontribs)) 

#any repeated fips?
bycounty_bycand %>% 
  count(lastname, fips) %>% 
  filter(n > 1)

#write to file
write_csv(bycounty_bycand, "output/bycounty_bycand.csv")


#reshaped version to wide
test_c <- bycounty_bycand %>%
  select(lastname, fips, sum_in_county)

test_c_wide <- test_c %>%
  spread(lastname, sum_in_county)

bycounty_bycand_wide <- test_c_wide

#write to file
write_csv(bycounty_bycand_wide, "output/bycounty_bycand_wide.csv")



#### COMPARING TWO DIFFERENT CANDIDATES' ZIP CODE PERFORMANCE ####

# select first candidate
cand1 <- "Booker"

z_cand1 <- byzip_bycand %>% 
  filter(lastname == cand1) %>% 
  select(zip5, cand1_contribs = sumcontribs)
  
# select second candidate
cand2 <- "Harris"

z_cand2 <- byzip_bycand %>% 
  filter(lastname == cand2) %>% 
  select(zip5, cand2_contribs = sumcontribs)  


### join to compare cand1 and cand2 in each zip
zipcompare <- full_join(z_cand1, z_cand2)

#change NAs to 0
zipcompare <- zipcompare %>% 
  replace(., is.na(.), 0)

#calculate winner and money spread
zipcompare <- zipcompare %>% 
  mutate(
    winner = ifelse(cand1_contribs>cand2_contribs, cand1, cand2),
    advantage = abs(cand1_contribs-cand2_contribs) 
  ) %>% 
  rename(!!cand1:=cand1_contribs, #this special coding pulls the variable name into the rename function
         !!cand2:=cand2_contribs) 

#join with zip lookup table
joined_temp <- left_join(zipcompare, ziplookup, by = c("zip5" = "zip_code"))
zipcompare <- joined_temp

#save to file
saveRDS(zipcompare, "zipcompare.rds")
