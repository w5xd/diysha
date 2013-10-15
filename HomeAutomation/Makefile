SUBS = readMotion thermostat hvac pcsensor-0.0.2 w5xdInsteon

.PHONY:	all $(SUBS)

all:	$(SUBS)

$(SUBS):
	cd $@ && make
