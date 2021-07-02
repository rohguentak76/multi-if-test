#! /bin/bash

while read line
do
        echo $line
        tunefs.lustre --erase-param mgsnode $line
        tunefs.lustre --mgsnode=10.73.20.101@tcp,10.73.20.11@tcp:10.73.20.102@tcp,10.73.20.12@tcp $line
done < dataset_list.txt
