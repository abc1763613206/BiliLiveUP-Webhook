#!/bin/bash
# set -x
# set -e

set +e
filename=$1
echo Processing $filename
echo 获取文件信息
cat $filename

tmp0=$(cat $filename | head -n 1 | tail -n 1 )
fulldate=$(echo $tmp0 | sed 's/_/-/g')
roomid=$(cat $filename | head -n 2 | tail -n 1)
username=$(cat $filename | head -n 3 | tail -n 1)
title=$(cat $filename | head -n 4 | tail -n 1)
nowdate=$(cat $filename | head -n 5 | tail -n 1)
tid=$(cat /opt/bililive/Hooks/Meta/$roomid.enabled | head -n 2 | tail -n 1)
date=${tmp0:2:8}
dirname=$roomid\_$username

groupid=$(cat $filename | head -n 7 | tail -n 1)
qq_endpoint=$(cat /opt/bililive/Hooks/qqpush.info | head -n 1 | tail -n 1)
qq_token=$(cat /opt/bililive/Hooks/qqpush.info | head -n 2 | tail -n 1)

preferred_line=ws

echo 执行 B 站上传
OLDIFS="$IFS"  #备份旧的IFS变量
IFS=$'\n'   #修改分隔符为换行符
uploadstate=$(cat /opt/bililive/Hooks/Meta/RecState/$roomid/uploaded.info)
if [[ "$uploadstate" == "initial" ]]; then
    echo "主播 [$username]($roomid) 未上传过录像，正在上传首个录像"
    cp template_single.yaml $roomid\_single.yaml
    sed -i "s/<roomid>/$roomid/g" $roomid\_single.yaml
    sed -i "s/<username>/$username/g" $roomid\_single.yaml
    sed -i "s/<title>/$title/g" $roomid\_single.yaml
    sed -i "s/<fulldate>/$fulldate/g" $roomid\_single.yaml
    sed -i "s/<date>/$date/g" $roomid\_single.yaml
    sed -i "s/<tid>/$tid/g" $roomid\_single.yaml
    curname=$(cat /opt/bililive/Hooks/Meta/RecState/$roomid/lastfile.info)
    echo "最后一次文件为 $curname"
    sed -i "s|<relativepath>|$curname|g" $roomid\_single.yaml
    echo "processing" > /opt/bililive/Hooks/Meta/RecState/$roomid/uploaded.info
    ./biliup-rs upload -c $roomid\_single.yaml > $roomid\_upload.log
    cat $roomid\_upload.log
    result=$(cat $roomid\_upload.log | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" | grep "投稿成功") 
    Count=0
    while [[ "$result" == "" ]]; do
        Count=$((Count+1))
        if [[ $Count -gt 4 ]]; then
            echo "上传失败，重试次数过多，放弃上传"
            break
        fi
        echo "上传失败，正在重试"
        ./biliup-rs upload -c $roomid\_single.yaml > $roomid\_upload.log
        result=$(cat $roomid\_upload.log | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g" | grep "投稿成功") 
    done
    if [[ "$result" != "" ]]; then
        bvid=$(cat $roomid\_upload.log | sed 's/,/\n/g' | grep '"bvid":' | awk -F "[\"\"]" '{print $4}')
        echo "上传成功，bvid 为 $bvid"
        curl --location  --request POST $qq_endpoint \
        --header 'Content-Type: application/json' \
        --data-raw "{
	    \"token\" : \"$qq_token\",
            \"send_to_group\": $groupid,
            \"content\": \"$(TZ=UTC-8 date "+%Y-%m-%d %H:%M:%S") 上传成功，预计（尚未审核）链接为：https://www.bilibili.com/video/$bvid\"
        }"
        echo $bvid > /opt/bililive/Hooks/Meta/RecState/$roomid/uploaded.info
    else
        curl --location  --request POST $qq_endpoint \
        --header 'Content-Type: application/json' \
        --data-raw "{
	    \"token\" : \"$qq_token\",
            \"send_to_group\": $groupid,
            \"content\": \"在初次上传的过程中发生致命的上传错误，请检查日志！\"
        }"
        echo "no" > /opt/bililive/Hooks/Meta/RecState/$roomid/uploaded.info
    fi
else
    echo "主播 [$username]($roomid) 已尝试上传录像，无需初始化上传"
fi
IFS="$OLDIFS"


OLDIFS="$IFS"  #备份旧的IFS变量
IFS=$'\n'   #修改分隔符为换行符
if [[ "$uploadstate" == "processing" ]]; then
    echo "主播 [$username]($roomid) 正在尝试上传，等待上传完毕后另行追加"
    exit
fi

# 上传完毕后追加上传
mkdir -p /opt/bililive/Archive/$roomid
echo "主播 [$username]($roomid) 已上传过录像，正在尝试追加上传"
bvid=$(cat /opt/bililive/Hooks/Meta/RecState/$roomid/uploaded.info)
echo "上一次上传视频的 bvid $bvid，尝试追加视频"
for j in $(ls /opt/bililive/Hooks/Meta/RecState/$roomid/files/*.info); do
    i=/opt/bililive/Work/$(cat $j)
    echo "发现视频 $(basename $i .flv)"
    echo "$i"
    Count=0
    while [[ ! $(./biliup-rs show $bvid) =~ $(basename $i .flv) ]]; do
        Count=$((Count+1))
        if [[ $Count -gt 4 ]]; then
            echo "上传失败，重试次数过多，放弃上传"
            break
        fi
        echo "尝试上传.... $(basename $i .flv)"
        ./biliup-rs append --vid $bvid --line $preferred_line --limit 30 "$i"
    done
    if [[ $(./biliup-rs show $bvid) =~ $(basename $i .flv) ]]; then 
        echo "成功上传 $(basename $i .flv)"
	    mv $i /opt/bililive/Archive/$roomid/
        rm -rf $j
    else
        echo "上传不成功，重试.... $(basename $i .flv)"
        ./biliup-rs append --vid $bvid --line $preferred_line --limit 30 "$i"
    fi
done


# 批量转码为ts文件

#for i in $(ls /opt/bililive/Work/$dirname/); do
#    for j0 in $(ls /opt/bililive/Work/$dirname/$i/*.flv | sed 's/ /WH1TESPACE/g'); do
#        j=$(echo $j0 | sed 's/WH1TESPACE/ /g')
#        echo "正在转码 $j"
#        mkdir -p /opt/bililive/Work/$dirname/$i/Converted/
#        ffmpeg -hide_banner -y -i "$j" -c copy -f mpegts "/opt/bililive/Work/$dirname/$i/Converted/$(basename "$j" .flv).ts"
#        # echo /opt/bililive/Work/$dirname/$i/Converted/$(basename $j .flv).ts
#    done
#done

IFS="$OLDIFS"

# 删除过期文件
find /opt/bililive/Archive/*/* -mtime +1 -delete

