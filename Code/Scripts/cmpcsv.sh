#!/bin/bash
# compare two .csv files

cd ~/Development/PacificMasters/PMSTopTen/Generated-2017
~/bup/pc2unix < Top10ExcelResults.csv >top10.csv
pushd ~/Development/PacificMasters/PMSTopTen/Generated-2017-1Group
~/bup/pc2unix < Top10ExcelResults.csv >top10.csv
diff top10.csv ~/Development/PacificMasters/PMSTopTen/Generated-2017