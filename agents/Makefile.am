#
# Makefile.am for y2c_mail/agents
#
# $Id$
#

agentsdir = $(YAST2DIR)/servers_non_y2
scrconfdir = $(YAST2DIR)/scrconf

agents_SCRIPTS = ag_mailtable ag_fetchmailrc

scrconf_DATA = \
	cfg_amavis.scr		\
	cfg_mail.scr		\
	cfg_postfix.scr		\
	cfg_sendmail.scr	\
	mail_fetchmail.scr	\
	mail_p_aliases.scr	\
	mail_p_canonical.scr	\
	mail_p_virtual.scr	\
	mail_s_aliases.scr	\
	mail_s_generics.scr	\
	mail_s_virtuser.scr

TESTS = test-fetchmailrc test-mailtable
testdata = test-fetchmailrc.in test-fetchmailrc.out \
	test-mailtable-1.in test-mailtable-1.out \
	test-mailtable-2.in test-mailtable-2.out

EXTRA_DIST = $(agents_SCRIPTS) $(scrconf_DATA) $(TESTS) $(testdata)
