include $(TOPDIR)/rules.mk

PKG_NAME:=mihomo
PKG_VERSION:=1.18.0
PKG_RELEASE:=1

PKG_MAINTAINER:=SubMiHomo QA
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/mihomo
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Mihomo proxy core (integration dummy)
  URL:=https://github.com/Conv3lsive/SubMiHomo
  PKGARCH:=all
endef

define Package/mihomo/description
  Dummy Mihomo binary used for SubMiHomo integration testing. Replaces the
  real proxy core so package lifecycle, procd startup, and rpcd calls can be
  exercised without a real upstream proxy.
endef

define Build/Compile
endef

define Package/mihomo/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/mihomo $(1)/usr/bin/mihomo
endef

$(eval $(call BuildPackage,mihomo))
