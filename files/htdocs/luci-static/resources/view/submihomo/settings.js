'use strict';
'require view';
'require rpc';
'require ui';

var callGetConfig = rpc.declare({
	object: 'submihomo',
	method: 'get_config',
	expect: {}
});

var callSetConfig = rpc.declare({
	object: 'submihomo',
	method: 'set_config',
	params: ['main', 'bypass'],
	expect: {}
});

var callRestart = rpc.declare({
	object: 'submihomo',
	method: 'restart',
	expect: {}
});

var CRITICAL_FIELDS = [
	'dns_mode', 'external_controller_port', 'external_controller_secret',
	'allow_lan_access', 'bypass_china', 'bypass_china_geoip_code',
	'dns_nameserver', 'dns_fallback', 'dns_fallback_filter_geoip'
];

return view.extend({
	load: function() {
		return L.resolveDefault(callGetConfig(), {main:{}, bypass:{address:[]}});
	},

	render: function(cfg) {
		var self = this;
		var main = (cfg && cfg.main) ? cfg.main : {};
		var bypass = (cfg && cfg.bypass) ? cfg.bypass : {address:[]};
		var origMain = Object.assign({}, main);

		var secretIsSet = main.external_controller_secret === 'REDACTED';

		function row(label, input, help) {
			var children = [
				E('label', {class:'cbi-value-title'}, label),
				E('div', {class:'cbi-value-field'}, [input])
			];
			if (help) children.push(E('div', {class:'cbi-value-description'}, help));
			return E('div', {class:'cbi-value'}, children);
		}

		function sel(id, opts, cur) {
			return E('select', {id:id}, opts.map(function(o) {
				return E('option', {value:o[0], selected: cur===o[0] ? 'selected':null}, o[1]);
			}));
		}

		var dnsMode = sel('sm-dns-mode',
			[['fake-ip', _('Fake-IP (recommended — faster, better domain matching)')],
			 ['real-ip', _('Real-IP (simpler — resolves real IPs before proxying)')]],
			main.dns_mode || 'fake-ip');

		var logLevel = sel('sm-log-level',
			[['silent','Silent'],['error','Error'],['warning','Warning (default)'],
			 ['info','Info'],['debug','Debug (verbose — use for troubleshooting only)']],
			main.log_level || 'warning');

		var ctrlPort = E('input', {type:'number', id:'sm-ctrl-port',
			min:'1024', max:'65535',
			value: main.external_controller_port || '9090'});

		var allowLan = E('input', {type:'checkbox', id:'sm-allow-lan',
			checked: main.allow_lan_access === '1' ? 'checked' : null});

		var bypassChina = E('input', {type:'checkbox', id:'sm-bypass-china',
			checked: main.bypass_china === '1' ? 'checked' : null});

		var geoipCode = E('input', {type:'text', id:'sm-geoip-code',
			value: main.bypass_china_geoip_code || 'CN', style:'width:80px;text-transform:uppercase'});

		var dashRepo = E('input', {type:'text', id:'sm-dash-repo',
			value: main.dashboard_repo || 'Zephyruso/zashboard', style:'width:300px'});

		var userAgent = E('input', {type:'text', id:'sm-user-agent',
			value: main.subscription_user_agent || 'SubMiHomo/1.0', style:'width:300px'});

		var dnsNameserver = E('input', {type:'text', id:'sm-dns-nameserver',
			value: main.dns_nameserver || 'https://1.1.1.1/dns-query https://8.8.8.8/dns-query',
			style:'width:100%', placeholder:'Space-separated DoH/DoT/plain DNS URLs'});

		var dnsFallback = E('input', {type:'text', id:'sm-dns-fallback',
			value: main.dns_fallback || 'https://1.0.0.1/dns-query',
			style:'width:100%', placeholder:'Fallback DNS (fake-ip mode only)'});

		var dnsFbGeoip = E('input', {type:'checkbox', id:'sm-dns-fb-geoip',
			checked: (main.dns_fallback_filter_geoip || '1') === '1' ? 'checked' : null});

		// Secret field with change toggle
		var secretDisplay = E('div', {id:'sm-secret-display'}, [
			E('span', {style:'font-family:monospace'},
				secretIsSet ? '••••••••' : E('em', {style:'color:#f44336'}, _('(not set — dashboard is unprotected)'))),
			' ',
			E('button', {class:'btn cbi-button-neutral', click: function() {
				document.getElementById('sm-secret-display').style.display = 'none';
				document.getElementById('sm-secret-input-row').style.display = '';
			}}, _('Change'))
		]);
		var secretInputRow = E('div', {id:'sm-secret-input-row', style:'display:none'}, [
			E('input', {type:'password', id:'sm-secret-input',
				placeholder: _('New secret (min 16 chars recommended)'), style:'width:300px'})
		]);

		var noSecretWarn = (!secretIsSet)
			? E('div', {class:'alert-message warning'}, [
				E('p', {}, _('No controller secret is set. Anyone on your LAN can access the dashboard and API without authentication. Set a secret to protect it.'))
			  ])
			: E('span', {});

		// Dynamic bypass list
		var bypassAddrs = Array.isArray(bypass.address) ? bypass.address.slice() : [];
		var bypassContainer = E('div', {id:'sm-bypass-list'});

		function renderBypassList(addrs) {
			bypassContainer.innerHTML = '';
			addrs.forEach(function(addr, i) {
				bypassContainer.appendChild(E('div', {style:'margin-bottom:4px;display:flex;gap:4px'}, [
					E('input', {type:'text', value:addr, 'data-idx':String(i),
						class:'sm-bypass-entry', style:'width:220px;font-family:monospace'}),
					E('button', {class:'btn cbi-button-negative btn-sm', click: function() {
						addrs.splice(i, 1); renderBypassList(addrs);
					}}, '✕')
				]));
			});
			bypassContainer.appendChild(E('button', {class:'btn cbi-button-neutral', click: function() {
				addrs.push(''); renderBypassList(addrs);
			}}, _('+ Add')));
		}
		renderBypassList(bypassAddrs);

		var errBanner = E('div', {id:'sm-settings-error', style:'display:none', class:'alert-message danger'});

		function doSave() {
			var errEl = document.getElementById('sm-settings-error');
			errEl.style.display = 'none';

			var newMain = {
				dns_mode:                     document.getElementById('sm-dns-mode').value,
				log_level:                    document.getElementById('sm-log-level').value,
				external_controller_port:     document.getElementById('sm-ctrl-port').value,
				allow_lan_access:             document.getElementById('sm-allow-lan').checked ? '1' : '0',
				bypass_china:                 document.getElementById('sm-bypass-china').checked ? '1' : '0',
				bypass_china_geoip_code:      document.getElementById('sm-geoip-code').value.toUpperCase(),
				dashboard_repo:               document.getElementById('sm-dash-repo').value,
				subscription_user_agent:      document.getElementById('sm-user-agent').value,
				dns_nameserver:               document.getElementById('sm-dns-nameserver').value,
				dns_fallback:                 document.getElementById('sm-dns-fallback').value,
				dns_fallback_filter_geoip:    document.getElementById('sm-dns-fb-geoip').checked ? '1' : '0'
			};

			var secretInputEl = document.getElementById('sm-secret-input');
			if (secretInputEl.parentElement.style.display !== 'none') {
				newMain.external_controller_secret = secretInputEl.value;
			} else {
				newMain.external_controller_secret = 'REDACTED';
			}

			var newBypass = [];
			document.querySelectorAll('.sm-bypass-entry').forEach(function(el) {
				var v = el.value.trim();
				if (v) newBypass.push(v);
			});

			var critical = CRITICAL_FIELDS.some(function(f) {
				return newMain[f] !== undefined && newMain[f] !== origMain[f] &&
					!(f === 'external_controller_secret' && newMain[f] === 'REDACTED');
			}) || JSON.stringify(newBypass) !== JSON.stringify(bypassAddrs);

			L.resolveDefault(callSetConfig(newMain, {address: newBypass}), {}).then(function(r) {
				if (r && r.success === false) {
					errEl.textContent = (r.errors || [r.error || _('Save failed')]).join('; ');
					errEl.style.display = '';
					return;
				}
				if (critical) {
					L.resolveDefault(callRestart(), {}).then(function() {
						ui.addNotification(null,
							E('p', _('Settings saved — SubMiHomo restarted to apply changes.')), 'info');
					});
				} else {
					ui.addNotification(null, E('p', _('Settings saved.')), 'info');
				}
				// Refresh
				L.resolveDefault(callGetConfig(), {}).then(function(nc) {
					if (nc && nc.main) Object.assign(origMain, nc.main);
				});
			});
		}

		return E('div', {}, [
			E('h2', {}, _('SubMiHomo — Settings')),
			E('div', {class:'cbi-section'}, [
				errBanner, noSecretWarn,
				E('div', {class:'cbi-section-node'}, [
					E('h3', {}, _('Proxy')),
					row(_('DNS Mode'), dnsMode,
						_('Fake-IP is recommended: clients receive synthetic IPs immediately, real resolution happens inside Mihomo.')),
					row(_('Bypass China traffic'), E('span', {}, [bypassChina, ' ', _('Enabled')]),
						_('Adds a GEOIP rule to route mainland Chinese destinations directly, bypassing the proxy.')),
					row(_('GeoIP country code'), geoipCode,
						_('Country code used for the bypass-china rule (default: CN). Must match a code in Mihomo\'s GeoIP database.')),
					E('h3', {}, _('Management')),
					row(_('Controller Port'), ctrlPort,
						_('Mihomo management API and dashboard port (default 9090).')),
					row(_('Controller Secret'), E('div', {}, [secretDisplay, secretInputRow]),
						_('Bearer token protecting the dashboard and API. Strongly recommended.')),
					row(_('Allow LAN Access'), E('span', {}, [allowLan, ' ', _('Enabled')]),
						_('When enabled: mixed proxy port and controller are accessible from LAN. When disabled: controller binds to 127.0.0.1 only.')),
					E('h3', {}, _('DNS')),
					row(_('Upstream nameservers'), dnsNameserver,
						_('Space-separated DNS resolver URLs (DoH, DoT, or plain). Used by Mihomo for all DNS queries.')),
					row(_('Fallback nameservers'), dnsFallback,
						_('Fallback resolvers (fake-ip mode only). Used when primary returns a GeoIP-filtered result.')),
					row(_('Fallback GeoIP filter'), E('span', {}, [dnsFbGeoip, ' ', _('Enabled')]),
						_('Use GeoIP filtering to decide when to use the fallback resolver. Recommended on.')),
					E('h3', {}, _('Advanced')),
					row(_('Log Level'), logLevel),
					row(_('Custom bypass addresses'), bypassContainer,
						_('Additional IPv4 CIDRs to bypass the proxy (e.g. VPN subnets, NAS IPs).')),
					row(_('Dashboard repository'), dashRepo,
						_('GitHub owner/repo for dashboard release downloads.')),
					row(_('Subscription user-agent'), userAgent,
						_('HTTP User-Agent sent when fetching the subscription. Some providers require a specific client string.'))
				]),
				E('div', {style:'margin-top:1em'}, [
					E('button', {class:'btn cbi-button-positive', click: doSave}, _('Save & Apply'))
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
