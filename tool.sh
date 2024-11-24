#!/bin/bash   

# 检查是否以 root 用户运行
if [ "$(id -u)" -ne 0 ]; then
  echo "错误：此脚本需要 root 权限。请使用 root 用户或通过 sudo 运行此脚本。"
  exit 1
fi

# 提示使用者
echo "--------------------------------------------------"
echo "请阅读以下注意事项："
echo "1. 此脚本的TCP调优操作对劣质线路无效"
echo "2. 小带宽用户默认参数基本就跑满了，无需进行调优"
echo "3. 调参消耗流量较多，请慎重调整"
echo "4. 请在执行该脚本前放行5201端口"
echo "5. 请先在客户端安装iperf3，不会安装/使用的请查看原贴"
echo "6. 请在晚高峰使用该脚本"
echo "--------------------------------------------------"
echo "作者：BlackSheep   原帖链接：https://www.nodeseek.com/post-197087-1"
echo "--------------------------------------------------"

# 选择方案
echo "请选择方案："
echo "1. 直接调整参数"
echo "2. 大参数+Traffic Control限速 (推荐)"
echo "3. 调整复原"

# 输入选择并检测是否有效
while true; do
    read -p "请输入方案编号 (1, 2 或 3): " choice
    if [[ "$choice" =~ ^[1-3]$ ]]; then
        break
    else
        echo "无效输入，请输入 1, 2 或 3。"
    fi
done
echo "--------------------------------------------------"

# 检查TCP拥塞控制算法与队列管理算法
current_cc=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
current_qdisc=$(sysctl net.core.default_qdisc | awk '{print $3}')

if [[ "$current_cc" != "bbr" ]]; then
    echo "当前TCP拥塞控制算法: $current_cc，未启用BBR，尝试启用BBR..."
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
fi

if [[ "$current_qdisc" != "fq" ]]; then
    echo "当前队列管理算法: $current_qdisc，未启用fq，尝试启用fq..."
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    sysctl -p
fi

# 检查iperf3是否已安装
if ! command -v iperf3 &> /dev/null; then
    echo "iperf3未安装，开始安装iperf3..."
    echo "--------------------------------------------------"
    apt-get update
    apt-get install -y iperf3
else
    echo "iperf3已经安装，跳过安装过程。"
    echo "--------------------------------------------------"
fi

# 提醒用户当前的TCP缓冲区参数大小
echo "当前TCP缓冲区参数大小如下："

# 查询并输出当前的TCP缓冲区参数大小
sysctl net.ipv4.tcp_wmem
sysctl net.ipv4.tcp_rmem
echo "--------------------------------------------------"

#!/bin/bash

# 获取用户输入的带宽和延迟，并确保输入有效
while true; do
    read -p "请输入本地带宽 (Mbps): " local_bandwidth
    # 验证输入是否为正整数且不为零
    if [[ "$local_bandwidth" =~ ^[1-9][0-9]*$ ]]; then
        break
    else
        echo "无效输入，请输入一个大于零的正整数作为本地带宽 (Mbps)。"
    fi
done

while true; do
    read -p "请输入服务器带宽 (Mbps): " server_bandwidth
    # 验证输入是否为正整数且不为零
    if [[ "$server_bandwidth" =~ ^[1-9][0-9]*$ ]]; then
        break
    else
        echo "无效输入，请输入一个大于零的正整数作为服务器带宽 (Mbps)。"
    fi
done

while true; do
    read -p "请输入往返时延/Ping值 (RTT, ms): " rtt
    # 验证输入是否为正整数且不为零
    if [[ "$rtt" =~ ^[1-9][0-9]*$ ]]; then
        break
    else
        echo "无效输入，请输入一个大于零的正整数作为往返时延 (ms)。"
    fi
done

echo "--------------------------------------------------"
echo "本地带宽：$local_bandwidth Mbps"
echo "服务器带宽：$server_bandwidth Mbps"
echo "往返时延/Ping值：$rtt ms"
echo "--------------------------------------------------"

# 计算BDP（带宽延迟积）
min_bandwidth=$((local_bandwidth < server_bandwidth ? local_bandwidth : server_bandwidth))
bdp=$((min_bandwidth * rtt * 1000 / 8))
echo "您的理论值为: $bdp 字节"
echo "--------------------------------------------------"

# 清除 sysctl.conf 中的 net.ipv4.tcp_wmem 和 net.ipv4.tcp_rmem 配置
sed -i '/^net\.ipv4\.tcp_wmem/d' /etc/sysctl.conf
sed -i '/^net\.ipv4\.tcp_rmem/d' /etc/sysctl.conf

# 确保文件末尾另起一空行
if [ -n "$(tail -c1 /etc/sysctl.conf)" ]; then
    echo "" >> /etc/sysctl.conf
fi

# 执行不同方案的操作 
case "$choice" in
  1)
    echo "方案一：直接调整参数"

    # 初始 new_value 赋值
    new_value=$bdp

    # 调整tcp_wmem 和 tcp_rmem
    sysctl -w net.ipv4.tcp_wmem="4096 16384 $new_value"
    sysctl -w net.ipv4.tcp_rmem="4096 87380 $new_value"
    echo "--------------------------------------------------"

    # 获取本机IP地址
    local_ip=$(wget -qO- --inet4-only http://icanhazip.com 2>/dev/null)

    if [ -z "$local_ip" ]; then
        local_ip=$(wget -qO- http://icanhazip.com)
    fi

    echo "您的本机IP是: $local_ip"


    # 启动iperf3服务端
    echo "启动iperf3服务端..."
    nohup iperf3 -s > /dev/null 2>&1 &

    # 提示执行iperf3命令
    echo "请在客户端执行以下命令来测试："
    echo "iperf3 -c $local_ip -R -t 30"
    echo "--------------------------------------------------"

    # 获取用户输入的Retr数值，并确保输入有效
    while true; do
        read -p "请输入iperf3测试结果中的Retr数目: " retr
        # 验证输入是否为大于或等于0的数字
        if [[ "$retr" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "无效输入，请输入一个大于或等于零的整数作为Retr数目。"
        fi
    done

    # 步骤一：重传≤100时，上调3MiB
    while [ "$retr" -le 100 ]; do
        echo "重传≤100，上调3MiB"
        new_value=$((new_value + 3 * 1024 * 1024))  # 每次上调3MiB
        sysctl -w net.ipv4.tcp_wmem="4096 16384 $new_value"
        sysctl -w net.ipv4.tcp_rmem="4096 87380 $new_value"
        echo "请执行以下命令进行iperf3测试："
        echo "iperf3 -c $local_ip -R -t 30"
        read -p "请输入Retr数: " retr
        echo "--------------------------------------------------"
        
        # 确保Retr数有效
        while [[ ! "$retr" =~ ^[0-9]+$ ]] || [ "$retr" -lt 0 ]; do
            echo "无效输入，请输入一个大于或等于零的整数作为Retr数目。"
            read -p "请输入Retr数: " retr
        done

        # 如果重传数超过100，进入步骤二
        if [ "$retr" -gt 100 ]; then
            break
        fi
    done

    # 步骤二：重传>100时，下调1MiB
    while [ "$retr" -gt 100 ]; do
        echo "重传>100，下调1MiB"
        new_value=$((new_value - 1024 * 1024))  # 每次下调1MiB
        sysctl -w net.ipv4.tcp_wmem="4096 16384 $new_value"
        sysctl -w net.ipv4.tcp_rmem="4096 87380 $new_value"
        echo "请执行以下命令进行iperf3测试："
        echo "iperf3 -c $local_ip -R -t 30"
        read -p "请输入Retr数: " retr
        echo "--------------------------------------------------"

        # 确保Retr数有效
        while [[ ! "$retr" =~ ^[0-9]+$ ]] || [ "$retr" -lt 0 ]; do
            echo "无效输入，请输入一个大于或等于零的整数作为Retr数目。"
            read -p "请输入Retr数: " retr
        done

        # 如果重传数≤ 100，跳出循环进入下一环节
        if [ "$retr" -le 100 ]; then
            break
        fi
    done

    # 最终下调0.5MiB并写入sysctl.conf
    new_value_final=$((new_value - 512 * 1024))  # 下调0.5MiB
    echo "重传再次≤100，下调0.5MiB，最终参数值：$new_value_final 字节"
    echo "net.ipv4.tcp_wmem=4096 16384 $new_value_final" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_rmem=4096 87380 $new_value_final" >> /etc/sysctl.conf
    sysctl -p

    # 停止iperf3服务端进程
    echo "停止iperf3服务端进程..."
    pkill iperf3

    echo "--------------------------------------------------"
    echo "脚本执行完毕！"
    ;;
  2)
    echo "方案二：大参数+Traffic Control限速 (推荐)"

    # 修改 sysctl.conf 并应用
    echo "net.ipv4.tcp_wmem=4096 16384 67108864" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_rmem=4096 87380 67108864" >> /etc/sysctl.conf
    sysctl -p

    # 显示当前网卡信息，让用户选择
    echo "当前网卡列表："
    ip link show
    echo "请根据以上列表输入用于互联网通信的网卡名称（一般为 eth0 或 wlan0，通常是第二个）"
    read -p "请输入网卡名称：" second_nic
    echo "--------------------------------------------------"

    # 检查网卡是否存在
    while true; do
        if ip link show "$second_nic" &>/dev/null; then
            break
        else
            # 提示用户输入错误并重新输入
            echo "错误：网卡 $second_nic 不存在，请检查输入并确保网卡已启用！"
            read -p "请输入正确的网卡名称: " second_nic
        fi
    done

    # 获取带宽值
    bandwidth_new=$((local_bandwidth < server_bandwidth ? local_bandwidth : server_bandwidth))
    echo "配置 Traffic Control，带宽为：${bandwidth_new} Mbps"

    # 配置 Traffic Control
    echo "配置Traffic Control..."
    tc qdisc del dev $second_nic root
    tc qdisc add dev $second_nic root handle 1:0 htb default 10
    tc class add dev $second_nic parent 1:0 classid 1:1 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit
    tc filter add dev $second_nic protocol ip parent 1:0 prio 1 u32 match ip src 0.0.0.0/0 flowid 1:1
    tc class add dev $second_nic parent 1:0 classid 1:2 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit
    tc filter add dev $second_nic protocol ip parent 1:0 prio 1 u32 match ip dst 0.0.0.0/0 flowid 1:2

    # 获取本机IP地址
    local_ip=$(wget -qO- --inet4-only http://icanhazip.com 2>/dev/null)

    if [ -z "$local_ip" ]; then
        local_ip=$(wget -qO- http://icanhazip.com)
    fi

    echo "您的本机IP是: $local_ip"

    # 启动 iperf3 服务端
    echo "启动 iperf3 服务端..."
    nohup iperf3 -s > /dev/null 2>&1 &  # 后台运行
    iperf3_pid=$!
    echo "iperf3 服务端启动，进程 ID：$iperf3_pid"
    echo "请在客户端执行以下命令测试："
    echo "iperf3 -c $local_ip -R -t 30"
    read -p "测试完成后，请按 Enter 键继续..."

    # 获取用户输入的Retr数值，并确保输入有效
    while true; do
        read -p "请输入iperf3测试结果中的Retr数目: " retr
        # 验证输入是否为大于或等于0的数字
        if [[ "$retr" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "无效输入，请输入一个大于或等于零的整数作为Retr数目。"
        fi
    done

    echo "--------------------------------------------------"

    # 步骤一：如果 Retr ≤ 100，上调限速值
    while [ "$retr" -le 100 ]; do
        bandwidth_new=$((bandwidth_new + 100))
        echo "重传≤100，限速值+100Mbps"

        # 配置新的限速值
        tc class change dev $second_nic classid 1:1 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit
        tc class change dev $second_nic classid 1:2 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit

        # 显示限速值调整结果
        echo "已调整限速值，新的限速值为：$bandwidth_new Mbps"
        
        # 等待用户输入新的 Retr 值
        read -p "请重新执行 iperf3 测试，并输入新的 Retr 值：" retr

        # 确保Retr数有效
        while [[ ! "$retr" =~ ^[0-9]+$ ]] || [ "$retr" -lt 0 ]; do
            echo "无效输入，请输入一个大于或等于零的整数作为Retr数目。"
            read -p "请输入Retr数: " retr
        done

        echo "--------------------------------------------------"

        # 如果重传数超过100，进入步骤二
        if [ "$retr" -gt 100 ]; then
            break
        fi
    done

    # 步骤二：重传>100 时，下调限速值
    while [ "$retr" -gt 100 ]; do
        bandwidth_new=$((bandwidth_new - 50))
        echo "重传>100，限速值-50Mbps"

        # 配置新的限速值
        tc class change dev $second_nic classid 1:1 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit
        tc class change dev $second_nic classid 1:2 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit

        # 显示限速值调整结果
        echo "已调整限速值，新的限速值为：$bandwidth_new Mbps"

        # 等待用户输入新的 Retr 值
        read -p "请重新执行 iperf3 测试，并输入新的 Retr 值：" retr

        # 确保Retr数有效
        while [[ ! "$retr" =~ ^[0-9]+$ ]] || [ "$retr" -lt 0 ]; do
            echo "无效输入，请输入一个大于或等于零的整数作为Retr数目。"
            read -p "请输入Retr数: " retr
        done

        echo "--------------------------------------------------"

        # 如果重传数≤ 100，跳出循环进入下一环节
        if [ "$retr" -le 100 ]; then
            break
        fi
    done

    # 写入 rc.local 以实现开机自启
    echo "#!/bin/bash" > /etc/rc.local
    echo "tc qdisc add dev $second_nic root handle 1:0 htb default 10" >> /etc/rc.local
    echo "tc class add dev $second_nic parent 1:0 classid 1:1 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit" >> /etc/rc.local
    echo "tc filter add dev $second_nic protocol ip parent 1:0 prio 1 u32 match ip src 0.0.0.0/0 flowid 1:1" >> /etc/rc.local
    echo "tc class add dev $second_nic parent 1:0 classid 1:2 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit" >> /etc/rc.local
    echo "tc filter add dev $second_nic protocol ip parent 1:0 prio 1 u32 match ip dst 0.0.0.0/0 flowid 1:2" >> /etc/rc.local
    echo "exit 0" >> /etc/rc.local

    chmod +x /etc/rc.local

    echo "Traffic Control 配置已完成"

    # 停止 iperf3 服务端进程
    echo "停止 iperf3 服务端进程..."
    kill $iperf3_pid
    echo "iperf3 服务端进程已停止"
    echo "--------------------------------------------------"
    echo "脚本执行完毕！"
    ;;
  3)
    echo "调整复原"

    # 清除 sysctl.conf 中的 net.ipv4.tcp_wmem 和 net.ipv4.tcp_rmem 设置
    sed -i '/net\.ipv4\.tcp_wmem/d' /etc/sysctl.conf
    sed -i '/net\.ipv4\.tcp_rmem/d' /etc/sysctl.conf
    echo "已从 /etc/sysctl.conf 中移除 net.ipv4.tcp_wmem 和 net.ipv4.tcp_rmem 设置。"

    # 设置默认值
    sysctl -w net.ipv4.tcp_wmem="4096 16384 4194304"
    sysctl -w net.ipv4.tcp_rmem="4096 87380 6291456"
    echo "已将 net.ipv4.tcp_wmem 和 net.ipv4.tcp_rmem 重置为默认值。"

    # 清除 /etc/rc.local 中的所有内容
    if [ -f /etc/rc.local ]; then
      > /etc/rc.local
      echo "#!/bin/bash" > /etc/rc.local
      chmod +x /etc/rc.local
      echo "已清空 /etc/rc.local 并添加基本脚本头部。"
    else
      echo "/etc/rc.local 文件不存在，无需清理。"
    fi

    # 用户输入网卡名称
    while true; do
      read -p "请输入网卡名称（被限速的网卡）： " iface
      if ip link show "$iface" &>/dev/null; then
        break
      else
        echo "网卡名称无效或不存在，请重新输入。"
      fi
    done

    # 删除 tc 限速
    if command -v tc &> /dev/null; then
      tc qdisc del dev "$iface" root 2>/dev/null
      tc qdisc del dev "$iface" ingress 2>/dev/null
      echo "已尝试清除网卡 $iface 的 tc 限速规则。"
    else
      echo "tc 命令不可用，未执行限速清理。"
    fi

    echo "--------------------------------------------------"
    echo "复原已完成"
    ;;
esac
