#
# Makefile.am for y2c_mail/src
#
# $Id$
#

clientsdir = $(YAST2DIR)/clients
includedir = $(YAST2DIR)/include/mail
menudir = $(YAST2DIR)/menuentries
modulesdir = $(YAST2DIR)/modules

clients_DATA =			\
	mail.ycp		\
	mail_auto.ycp	\
	mail_write.ycp

include_DATA =			\
	helps.ycp		\
	ui.ycp

menu_DATA =			\
	menuentry_mail.y2cc

modules_DATA =			\
	Mail.ycp

EXTRA_DIST = $(clients_DATA) $(include_DATA) $(menu_DATA) $(modules_DATA)
