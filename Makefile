include $(TOPDIR)/rules.mk

PKG_NAME:=submihomo
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=SubMiHomo Team
PKG_LICENSE:=MIT

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/submihomo
  SECTION:=net
  CATEGORY:=Network
  TITLE:=SubMiHomo Mihomo proxy service
  URL:=https://github.com/Conv3lsive/SubMiHomo
  DEPENDS:=+firewall4 +nftables +kmod-nft-tproxy +ip-full +wget-ssl +ca-certificates +gzip +jshn +rpcd
  PKGARCH:=all
endef

define Package/submihomo/description
  OpenWrt service wrapper for the Mihomo proxy core. Provides TPROXY
  transparent proxying, DNS hijack, firewall integration, and an rpcd
  management plugin.
endef

define Package/luci-app-submihomo
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=SubMiHomo LuCI interface
  URL:=https://github.com/Conv3lsive/SubMiHomo
  DEPENDS:=+submihomo +luci-base
  PKGARCH:=all
endef

define Package/luci-app-submihomo/description
  LuCI web interface for configuring and monitoring SubMiHomo.
endef

define Build/Compile
endef

define Package/submihomo/conffiles
/etc/config/submihomo
/etc/submihomo/templates/base.yaml.tmpl
endef

define Package/submihomo/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/submihomo $(1)/etc/init.d/submihomo
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/submihomo $(1)/etc/config/submihomo
	$(INSTALL_DIR) $(1)/etc/submihomo/templates
	$(INSTALL_DATA) ./files/etc/submihomo/templates/base.yaml.tmpl $(1)/etc/submihomo/templates/base.yaml.tmpl
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/submihomo-ctl $(1)/usr/bin/submihomo-ctl
	$(INSTALL_DIR) $(1)/usr/lib/submihomo
	$(INSTALL_BIN) ./files/usr/lib/submihomo/*.sh $(1)/usr/lib/submihomo/
	$(INSTALL_DIR) $(1)/usr/libexec/submihomo
	$(INSTALL_DIR) $(1)/usr/lib/rpcd
	$(INSTALL_BIN) ./files/usr/lib/rpcd/submihomo $(1)/usr/lib/rpcd/submihomo
endef

define Package/submihomo/postinst
#!/bin/sh
/etc/init.d/submihomo enable 2>/dev/null || true
exit 0
endef

define Package/submihomo/prerm
#!/bin/sh
/etc/init.d/submihomo stop 2>/dev/null || true
/etc/init.d/submihomo disable 2>/dev/null || true
exit 0
endef

define Package/luci-app-submihomo/install
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./files/usr/share/luci/menu.d/luci-app-submihomo.json $(1)/usr/share/luci/menu.d/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/luci-app-submihomo.json $(1)/usr/share/rpcd/acl.d/
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/submihomo
	$(INSTALL_DATA) ./files/htdocs/luci-static/resources/view/submihomo/*.js $(1)/www/luci-static/resources/view/submihomo/
endef

$(eval $(call BuildPackage,submihomo))
$(eval $(call BuildPackage,luci-app-submihomo))
