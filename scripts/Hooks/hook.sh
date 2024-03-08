#!/bin/bash

qq_endpoint=$(cat /opt/bililive/Hooks/qqpush.info | head -n 1 | tail -n 1)
qq_token=$(cat /opt/bililive/Hooks/qqpush.info | head -n 2 | tail -n 1)

# 根据指定文件是否存在判断是否开启 Hook
if [ ! -f "/opt/bililive/Hooks/Meta/$roomid.enabled" ]; then
    echo "主播 [$username]($roomid) 未开启 Hook，该次处理无效。"
    exit
fi

groupid=$(cat /opt/bililive/Hooks/Meta/$roomid.enabled | head -n 1 | tail -n 1)

if [[ "$EVENT_TYPE" == "StreamStarted" ]]; then
    # 主播开播逻辑
    curl --location  --request POST $qq_endpoint \
    --header 'Content-Type: application/json' \
    --data-raw "{
	\"token\" : \"$qq_token\",
        \"send_to_group\": $groupid,
        \"content\": \"主播[$username]($roomid) 开播啦！\n开播分区：$parent_area_id -> $child_area_id \n直播间标题：$title\n即刻围观：https://live.bilibili.com/$roomid\n[CQ:at,qq=all]\"
    }"
    # 写入开播日期
    mkdir -p /opt/bililive/Hooks/Meta/RecState/$roomid/files
    echo $(TZ=UTC-8 date '+%Y_%m_%d') > /opt/bililive/Hooks/Meta/RecState/$roomid/basic.info
    echo $roomid >> /opt/bililive/Hooks/Meta/RecState/$roomid/basic.info
    echo $username >> /opt/bililive/Hooks/Meta/RecState/$roomid/basic.info
    echo $title >> /opt/bililive/Hooks/Meta/RecState/$roomid/basic.info
    echo "initial" > /opt/bililive/Hooks/Meta/RecState/$roomid/uploaded.info
    echo $(TZ=UTC-8 date '+%Y_%m_%d') >> /opt/bililive/Hooks/Meta/RecState/$roomid/basic.info
    echo $(cat /opt/bililive/Hooks/Meta/$roomid.enabled | head -n 2 | tail -n 1) >> /opt/bililive/Hooks/Meta/RecState/$roomid/basic.info #tid
    echo $groupid >> /opt/bililive/Hooks/Meta/RecState/$roomid/basic.info
    #echo $(TZ=UTC-8 date '+%Y_%m_%d') > /opt/bililive/Hooks/$roomid.info
    exit
fi

if [[ "$EVENT_TYPE" == "FileClosed" ]]; then
    # 文件关闭 即已经产生了切片
    echo $relative_fpath > /opt/bililive/Hooks/Meta/RecState/$roomid/lastfile.info
    echo $relative_fpath > /opt/bililive/Hooks/Meta/RecState/$roomid/files/$(TZ=UTC-8 date '+%Y%m%d%H%M%S').info
    curup=$(cat /opt/bililive/Hooks/Meta/RecState/$roomid/uploaded.info)
    echo "主播 [$username]($roomid) 发生一次切片事件！\n生成文件：$relative_fpath \n当期录像状态：$curup"
    curl --location  --request POST $qq_endpoint \
    --header 'Content-Type: application/json' \
    --data-raw "{
    \"token\" : \"$qq_token\",
        \"send_to_group\": $groupid,
        \"content\": \"主播[$username]($roomid) 发生一次切片事件！\n生成文件：$relative_fpath \n当期录像状态：$curup\"
    }"
    /opt/bililive/Hooks/upn.sh /opt/bililive/Hooks/Meta/RecState/$roomid/basic.info
    exit
fi

if [[ "$EVENT_TYPE" == "StreamEnded" ]]; then
    # 主播下播逻辑
    curl --location  --request POST $qq_endpoint \
    --header 'Content-Type: application/json' \
    --data-raw "{
	\"token\" : \"$qq_token\",
        \"send_to_group\": $groupid,
        \"content\": \"主播[$username]($roomid) 下播啦！\"
    }"
    # 生成配置文件
    sed -i "5c $(TZ=UTC-8 date '+%Y_%m_%d')" /opt/bililive/Hooks/Meta/RecState/$roomid/basic.info
    sleep 3600
    /opt/bililive/Hooks/upn.sh /opt/bililive/Hooks/Meta/RecState/$roomid/basic.info
    echo Goodbye!
    echo $(TZ=UTC-8 date "+%Y-%m-%d %H:%M:%S")
    exit
fi



