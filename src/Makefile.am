#
# Makefile.am for y2c_mail/src
#
# $Id$
#

myyncludedir = $(yncludedir)/mail

client_DATA =			\
	mail.ycp		\
	mail_auto.ycp

myynclude_DATA =		\
	helps.ycp		\
	wj.ycp			\
	widgets.ycp		\
	ui.ycp

desktop_DATA =			\
	mail.desktop

module_DATA =			\
	MailAliases.ycp		\
	Mail.ycp


EXTRA_DIST = $(client_DATA) $(myynclude_DATA) $(module_DATA) $(desktop_DATA)

include $(top_srcdir)/Makefile.am.common
