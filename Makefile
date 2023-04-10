include $(TOPDIR)/rules.mk

PKG_NAME:=wstunnel
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=dandan <dandan@dandan.com>
PKG_LICENSE:=dandan

include $(INCLUDE_DIR)/package.mk

define Package/wstunnel
	SECTION:=net
	CATEGORY:=Network
	DEPENDS:=+libuwsc
	TITLE:=Web Sockets Tunnel (wstunnel)
	MAINTAINER:=dandan <dandan@dandan.com>
	PKGARCH:=all
endef

define Package/wstunnel/description
	   WStunnel creates an HTTPS tunnel that can connect servers sitting behind an HTTP proxy and firewall to clients on the internet. It differs \
		from many other projects by handling many concurrent tunnels allowing a central client (or set of clients)  \
	    to make requests to many servers sitting behind firewalls. Each client/server pair are joined through a rendez-vous token.
endef

define Build/Compile/Default
endef
Build/Compile = $(Build/Compile/Default)

define Package/wstunnel/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/wsclient.lua $(1)/usr/sbin/wsclient
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/wsclient.config $(1)/etc/config/wsclient
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/wsclient.init $(1)/etc/init.d/wsclient
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
