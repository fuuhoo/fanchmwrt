# fwx-qos — LuCI 每设备上下行限速（FanchmWrt）

基于 `nftables limit` 的每设备限速，给 FanchmWrt 加一个图形界面。

## 特点

- **零新增依赖**：只用固件自带的 nftables（`nft_limit.ko` 已在内核里），不装任何包、不动内核
- **不影响防火墙**：规则放在独立的 `inet fwx_qos` 表，`firewall` 规则 reload/重启都不受影响
- **IPv4 + IPv6 双向**：IPv6 地址按 MAC 从邻居表自动识别，设备换地址后 60 秒内自动更新
- **不占 CPU**：PPE 硬件转发照常工作，限速只在超速时丢包，实测路由器 CPU 0–3%（峰值 6%）

## 安装

在 Windows 上执行（替换 `<路由器密码>`）：

```
pscp -scp -pw '<路由器密码>' -hostkey 'SHA256:RRJa7Ps8c59eKIgyUk04qEQPwUw2i2x32ybmFSrSDIs' root/usr/sbin/fwx-qos-gen root@192.168.0.1:/usr/sbin/fwx-qos-gen
pscp -scp -pw '<路由器密码>' -hostkey 'SHA256:RRJa7Ps8c59eKIgyUk04qEQPwUw2i2x32ybmFSrSDIs' root/etc/init.d/fwx-qos root@192.168.0.1:/etc/init.d/fwx-qos
pscp -scp -pw '<路由器密码>' -hostkey 'SHA256:RRJa7Ps8c59eKIgyUk04qEQPwUw2i2x32ybmFSrSDIs' root/usr/lib/lua/luci/controller/fwx_qos.lua root@192.168.0.1:/usr/lib/lua/luci/controller/fwx_qos.lua
pscp -scp -pw '<路由器密码>' -hostkey 'SHA256:RRJa7Ps8c59eKIgyUk04qEQPwUw2i2x32ybmFSrSDIs' root/usr/lib/lua/luci/view/fwx_qos/qos.htm root@192.168.0.1:/usr/lib/lua/luci/view/fwx_qos/qos.htm
```

然后在路由器上：

```
mkdir -p /usr/lib/lua/luci/view/fwx_qos
chmod +x /usr/sbin/fwx-qos-gen /etc/init.d/fwx-qos
rm -f /tmp/luci-indexcache; rm -rf /tmp/luci-modulecache/*
uci -q batch <<EOF
delete fwx_qos
set fwx_qos.global=qos
set fwx_qos.global.enabled='1'
commit fwx_qos
EOF
/etc/init.d/fwx-qos enable
/etc/init.d/fwx-qos restart
```

页面入口：**系统 → 带宽限速**（`http://192.168.0.1/cgi-bin/luci/admin/system/fwx_qos`）。

> 注意：ash 是边读边执行脚本的，**覆盖 `/usr/sbin/fwx-qos-gen` 后必须 `/etc/init.d/fwx-qos restart`**，
> 否则正在运行的 watch 进程会按旧文件偏移继续执行，生成空规则。

## 使用

1. 在「从在线设备添加」下拉框选设备（列表来自 DHCP 租约 + IPv6 邻居表，含主机名/MAC/IP）
2. 点「添加」，在表格里填 **下行 KB/s**（设备接收方向）和 **上行 KB/s**（设备发送方向），0 表示不限
3. 点「保存并应用」，页面下方「当前生效规则」会显示真实 nft 规则和丢包计数

单位是 KB/s（1 KB = 1000 字节，与 nft 的 kbytes 一致）。实测：设 2048 KB/s，实测 1.97 MB/s，误差约 1.4%。

## 工作原理

生成的规则形如：

```
table inet fwx_qos {
	chain forward {
		type filter hook forward priority -1; policy accept;
		ip daddr 192.168.0.114 limit rate over 2048 kbytes/second burst 512 kbytes counter drop
		ip saddr 192.168.0.114 limit rate over 1024 kbytes/second burst 256 kbytes counter drop
		ip6 daddr 2409:... limit rate over 2048 kbytes/second burst 512 kbytes counter drop
		ip6 saddr 2409:... limit rate over 1024 kbytes/second burst 256 kbytes counter drop
	}
}
```

- 路由器视角，**设备收到的包是 daddr = 设备**，所以下行限速用 `daddr`；上行用 `saddr`
- `burst` 取速率的 1/4（最小 32KB）：不加 burst 时 nft 令牌桶会让实际速率掉到目标的 50% 左右
- 超速的包直接丢弃（令牌桶），不是排队整形，所以 UDP/语音会有抖动；TCP 能收敛到目标速率

## 命令行

```sh
/usr/sbin/fwx-qos-gen status    # 查看当前规则与计数器
/usr/sbin/fwx-qos-gen apply     # 重新生成并加载
/usr/sbin/fwx-qos-gen clear     # 清除所有限速
```

## 配置存储

`/etc/config/fwx_qos`（标准 UCI，可随固件备份一起保存）：

```
config qos 'global'
	option enabled '1'

config rule 'rule_1'
	option enabled '1'
	option name '客厅电视'
	option mac 'aa:bb:cc:dd:ee:ff'
	option ipv4 '192.168.0.100'
	option download '2048'
	option upload '1024'
```

## 卸载

```
/etc/init.d/fwx-qos stop
/etc/init.d/fwx-qos disable
rm -f /usr/sbin/fwx-qos-gen /etc/init.d/fwx-x-qos /etc/init.d/fwx-qos \
      /usr/lib/lua/luci/controller/fwx_qos.lua \
      /usr/lib/lua/luci/view/fwx_qos/qos.htm /etc/config/fwx_qos
rm -f /tmp/luci-indexcache; rm -rf /tmp/luci-modulecache/*
```

## 注意事项

- **不要开 fastnat（SFE 快速转发）**：SFE 会让已建立的连接绕过 nft 规则，限速失效。固件默认 `fastnat.global.enabled=0`，保持即可
- 这台机器（ipq6018）自带 QCA PPE 硬件转发，流量默认走硬件，限速只是额外的丢包判断，CPU 占用极低
- 若以后开启 `flow_offloading`（软件卸载），同样会让限速失效
