#
# Makefile.am for y2c_mail/agents
#
# $Id$
#

agent_SCRIPTS = ag_mailtable ag_fetchmailrc

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
testdata = test-fetchmailrc.in \
	test-fetchmailrc-i.out \
	test-fetchmailrc-o.out \
	test-mailtable-1.in test-mailtable-1.out \
	test-mailtable-2.in test-mailtable-2.out

EXTRA_DIST = $(agent_SCRIPTS) $(scrconf_DATA) $(TESTS) $(testdata)
