# multi-if-test

```
#pacemaker에서 노드 분리하기 

1. corosync.conf에서 노드정보 삭제
2. 클러스터 재시작
3. pcs cluster node clear ${node name}
```

```
# 파일 한줄 씩 읽어서 리소스 삭제
while read line; do pcs resource delete $line ; done < resource.txt
```
