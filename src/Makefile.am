#
# Makefile.am for y2c_mail/src
#
# $Id$
#

SUBDIRS = YaPI

myyncludedir = $(yncludedir)/mail
ldapschemadir  = /etc/openldap/schema

client_DATA =			\
	mail.ycp		\
	mail_auto.ycp		\
	\
        mail-server.ycp         \
        mail-server_auto.ycp    \
        mail-server_proposal.ycp


myynclude_DATA =		\
	helps.ycp		\
	wj.ycp			\
	widgets.ycp		\
	ui.ycp			\
	\
	mail-server_helps.ycp   \
        mail-server_wizards.ycp \
        mail-server_dialogs.ycp \
        mail-server_complex.ycp

desktop_DATA =			\
	mail.desktop

module_DATA =			\
	Mail.ycp		\
	MailServer.ycp

ldapschema_DATA = suse-mailserver.schema

rncdir =  $(schemadir)/autoyast/rnc
rnc_DATA = mail.rnc

mail:
	ln -sf . mail

ycpchook = mail

EXTRA_DIST = $(client_DATA) $(myynclude_DATA) $(module_DATA) $(desktop_DATA) $(rnc_DATA) \
             $(ldapschema_DATA)

include $(top_srcdir)/Makefile.am.common
