#
# Copyright (C) 2026 fanchmwrt contributors
#
# This is free software, licensed under the MIT License.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-fwx-qos
PKG_VERSION:=1.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-fwx-qos
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=FanchmWrt per-device bandwidth limit
  DEPENDS:=+luci-base
  PKGARCH:=all
endef

define Package/luci-app-fwx-qos/description
  Per-device upload/download rate limiting for FanchmWrt, implemented with
  nftables limit expressions. No extra kernel modules required.
endef

define Package/luci-app-fwx-qos/conffiles
/etc/config/fwx_qos
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-fwx-qos/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./files/fwx_qos.lua $(1)/usr/lib/lua/luci/controller/fwx_qos.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/fwx_qos
	$(INSTALL_DATA) ./files/qos.htm $(1)/usr/lib/lua/luci/view/fwx_qos/qos.htm
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/fwx-qos-gen $(1)/usr/sbin/fwx-qos-gen
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/fwx-qos.init $(1)/etc/init.d/fwx-qos
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/fwx_qos.config $(1)/etc/config/fwx_qos
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./files/luci-app-fwx-qos.json $(1)/usr/share/luci/menu.d/luci-app-fwx-qos.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/rpcd-acl.json $(1)/usr/share/rpcd/acl.d/luci-app-fwx-qos.json
endef

define Package/luci-app-fwx-qos/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/fwx-qos enable
/etc/init.d/fwx-qos restart
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache/*
/etc/init.d/rpcd restart >/dev/null 2>&1
exit 0
endef

define Package/luci-app-fwx-qos/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/fwx-qos stop
/etc/init.d/fwx-qos disable
exit 0
endef

$(eval $(call BuildPackage,luci-app-fwx-qos))
