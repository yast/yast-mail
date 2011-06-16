#
# Makefile.am for y2c_mail/agents
#
# $Id$
#

agent_SCRIPTS = ag_fetchmailrc \
		ag_smtp_auth \
		ag_mailtable \
		setup_dkim_verifying.pl \
		ag_mailconfig \
		ag_postfix_mastercf \
		MasterCFParser.pm \
		ag_mail_ldaptable \
                ag_cyrus_conf \
		CyrusConfParser.pm

scrconf_DATA = \
	cfg_amavis.scr		\
	cfg_mail.scr		\
	cfg_postfix.scr		\
	cfg_sendmail.scr	\
	mail_aliases.scr	\
	mail_fetchmail.scr	\
	mail_p_auth.scr		\
	mail_p_canonical.scr	\
	mail_p_virtual.scr	\
	mail_s_auth.scr		\
	mail_s_generics.scr	\
	mail_s_virtuser.scr     \
	\
	mail_maincf.scr \
	mail_saslpasswd.scr \
	mail_mastercf.scr \
	etc_imapd_conf.scr \
        mail_ldaptable.scr \
	mail_cyrusconf.scr \
	cfg_fetchmail.scr

fillup_DATA =  sysconfig.mail

# ag_fetchmailrc is tested in testsuite dir
TESTS = test-mailtable
# ycp normalization does not work yet
XFAIL_TESTS = test-mailtable
testdata = \
	test-mailtable-1.in test-mailtable-1.out \
	test-mailtable-2.in test-mailtable-2.out \
	test-mailtable-3.in test-mailtable-3.out \
	test-mailtable-4.in test-mailtable-4.out \
	test-mailtable-18487.in test-mailtable-18487.out

EXTRA_DIST = $(agent_SCRIPTS) $(scrconf_DATA) $(TESTS) $(testdata) $(fillup_DATA)
