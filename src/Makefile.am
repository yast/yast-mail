#
# Makefile.am for y2c_mail/src
#
# $Id$
#

agentsdir = $(YAST2DIR)/servers_non_y2
clientsdir = $(YAST2DIR)/clients
includedir = $(YAST2DIR)/include/mail
menudir = $(YAST2DIR)/menuentries
modulesdir = $(YAST2DIR)/modules

agents_SCRIPTS = ag_mailtable ag_fetchmailrc

clients_DATA =			\
	mail.ycp		\
	mail_auto.ycp	\
	mail_summary.ycp	\
	mail_write.ycp

include_DATA =			\
	helps.ycp		\
	misc.ycp		\
	ui.ycp

menu_DATA =			\
	menuentry_mail.ycp

modules_DATA =			\
	Mail.ycp

EXTRA_DIST = $(agents_SCRIPTS) $(clients_DATA) $(include_DATA) $(menu_DATA) $(modules_DATA)
