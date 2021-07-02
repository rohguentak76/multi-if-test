#! /bin/bash
i=0
while read line;
do
        echo $line
        echo $i
        zpool create OST$i -o multihost=on $line
        ((i=i+1))
done < mpath.txt
