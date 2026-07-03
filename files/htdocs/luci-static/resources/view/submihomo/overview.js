'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var callStatus = rpc.declare({
	object: 'submihomo',
	method: 'status',
	expect: {}
});

var callStart = rpc.declare({
	object: 'submihomo',
	method: 'start',
	expect: {}
});

var callStop = rpc.declare({
	object: 'submihomo',
	method: 'stop',
	expect: {}
});

var callRestart = rpc.declare({
	object: 'submihomo',
	method: 'restart',
	expect: {}
});

var callDiagnostics = rpc.declare({
	object: 'submihomo',
	method: 'run_diagnostics',
	expect: {}
});

var callDownloadDashboard = rpc.declare({
	object: 'submihomo',
	method: 'download_dashboard',
	expect: {}
});

return view.extend({
	load: function() {
		return Promise.all([
			L.resolveDefault(callStatus(), {}),
			L.resolveDefault(callDiagnostics(), {checks:[]})
		]);
	},

	_renderStatus: function(status) {
		var running = status.running === true;
		var dot = E('span', {
			style: 'display:inline-block;width:12px;height:12px;border-radius:50%;margin-right:6px;background:' +
				(running ? '#4caf50' : '#f44336')
		});
		var label = running
			? _('Running') + (status.pid ? ' (pid ' + status.pid + ')' : '')
			: _('Stopped');

		var info = E('div', {class:'cbi-section-node'}, [
			E('p', {}, [dot, label]),
		]);

		if (status.version) {
			info.appendChild(E('p', {}, _('Mihomo version: ') + status.version));
		}
		if (status.subscription_url_masked && status.subscription_url_masked.length > 0) {
			info.appendChild(E('p', {}, _('Subscription: ') + status.subscription_url_masked));
		}
		if (status.last_update) {
			var d = new Date(status.last_update * 1000);
			info.appendChild(E('p', {}, _('Last update: ') + d.toLocaleString()));
		}
		if (status.proxy_count !== undefined) {
			info.appendChild(E('p', {}, _('Proxies loaded: ') + status.proxy_count));
		}
		info.appendChild(E('p', {}, _('DNS mode: ') + (status.dns_mode || 'unknown')));
		return info;
	},

	_renderActions: function(status) {
		var running = status.running === true;
		var self = this;

		var startBtn = E('button', {
			class: 'btn cbi-button-positive',
			disabled: running ? 'disabled' : null,
			click: function() {
				ui.showModal(_('Starting…'), [E('p', _('Starting SubMiHomo…'))]);
				L.resolveDefault(callStart(), {}).then(function(r) {
					ui.hideModal();
					if (r && r.success === false) {
						ui.addNotification(null, E('p', _('Start failed: ') + (r.error || '')), 'danger');
					}
					self._refresh();
				});
			}
		}, _('Start'));

		var stopBtn = E('button', {
			class: 'btn cbi-button-negative',
			disabled: !running ? 'disabled' : null,
			click: function() {
				ui.showModal(_('Confirm'), [
					E('p', _('Stopping SubMiHomo will disable proxying for all clients.')),
					E('div', {class:'right'}, [
						E('button', {class:'btn', click: ui.hideModal}, _('Cancel')),
						E('button', {class:'btn cbi-button-negative', click: function() {
							ui.hideModal();
							L.resolveDefault(callStop(), {}).then(function() { self._refresh(); });
						}}, _('Stop'))
					])
				]);
			}
		}, _('Stop'));

		var restartBtn = E('button', {
			class: 'btn cbi-button-action',
			click: function() {
				L.resolveDefault(callRestart(), {}).then(function() {
					ui.addNotification(null, E('p', _('Service restarting…')), 'info');
					self._refresh();
				});
			}
		}, _('Restart'));

		return E('div', {class:'cbi-section-node'}, [startBtn, ' ', stopBtn, ' ', restartBtn]);
	},

	_renderDiagnostics: function(diag) {
		var checks = (diag && diag.checks) ? diag.checks : [];
		var rows = checks.map(function(c) {
			var color = {ok:'#4caf50', fail:'#f44336', warn:'#ff9800', skip:'#9e9e9e'}[c.status] || '#9e9e9e';
			var dot = E('span', {style:'color:'+color+';font-weight:bold'}, c.status.toUpperCase());
			return E('tr', {}, [
				E('td', {}, c.name),
				E('td', {}, dot),
				E('td', {}, c.message)
			]);
		});
		return E('table', {class:'table cbi-section-table'}, [
			E('tr', {class:'tr table-titles'}, [
				E('th', {}, _('Check')),
				E('th', {}, _('Status')),
				E('th', {}, _('Detail'))
			])
		].concat(rows));
	},

	_renderDashboardSection: function(status) {
		var self = this;
		var hasDash = status.has_dashboard === true;
		var ctrlPort = status.ctrl_port || 9090;
		var host = window.location.hostname;

		var dashLink = E('a', {
			href: 'http://' + host + ':' + ctrlPort + '/ui',
			target: '_blank',
			class: 'btn cbi-button-action',
			disabled: (!hasDash || !status.running) ? 'disabled' : null
		}, _('Open Dashboard ↗'));

		var downloadBtn = E('button', {
			class: 'btn cbi-button-neutral',
			click: function() {
				ui.showModal(_('Downloading Dashboard'), [E('p', _('Downloading Zashboard from GitHub, please wait…'))]);
				L.resolveDefault(callDownloadDashboard(), {}).then(function(r) {
					ui.hideModal();
					if (r && r.success) {
						ui.addNotification(null, E('p', _('Dashboard downloaded: ') + (r.version||'')), 'info');
					} else {
						ui.addNotification(null, E('p', _('Dashboard download failed: ') + ((r&&r.error)||'')), 'danger');
					}
					self._refresh();
				});
			}
		}, _('Download Dashboard'));

		var versionSpan = hasDash && status.dashboard_version
			? E('span', {}, ' v' + status.dashboard_version)
			: E('span', {style:'color:#f44336'}, ' ' + _('Not installed'));

		return E('div', {class:'cbi-section-node'}, [
			E('p', {}, [_('Dashboard:'), versionSpan]),
			E('p', {}, [hasDash ? dashLink : downloadBtn])
		]);
	},

	_refresh: function() {
		var self = this;
		Promise.all([
			L.resolveDefault(callStatus(), {}),
			L.resolveDefault(callDiagnostics(), {checks:[]})
		]).then(function(data) {
			var status = data[0], diag = data[1];
			var statusEl = document.getElementById('sm-status-section');
			var actionsEl = document.getElementById('sm-actions-section');
			var diagEl = document.getElementById('sm-diag-section');
			var dashEl = document.getElementById('sm-dashboard-section');
			if (statusEl) { statusEl.innerHTML=''; statusEl.appendChild(self._renderStatus(status)); }
			if (actionsEl) { actionsEl.innerHTML=''; actionsEl.appendChild(self._renderActions(status)); }
			if (diagEl) { diagEl.innerHTML=''; diagEl.appendChild(self._renderDiagnostics(diag)); }
			if (dashEl) { dashEl.innerHTML=''; dashEl.appendChild(self._renderDashboardSection(status)); }
		});
	},

	render: function(data) {
		var status = data[0] || {};
		var diag = data[1] || {checks:[]};
		var self = this;

		// Setup auto-refresh
		poll.add(function() { return self._refresh(); }, 10);

		// No-subscription banner
		var banner = [];
		if (!status.subscription_url || status.subscription_url === '') {
			banner.push(E('div', {class:'alert-message warning'}, [
				E('h4', {}, _('Welcome to SubMiHomo!')),
				E('p', {}, _("You haven't added a subscription yet. Add your subscription URL to start proxying traffic.")),
				E('a', {href: L.url('admin/services/submihomo/subscription'), class:'btn cbi-button-action'}, _('Go to Subscription →'))
			]));
		}

		return E('div', {}, banner.concat([
			E('h2', {}, _('SubMiHomo — Overview')),

			E('div', {class:'cbi-section'}, [
				E('h3', {}, _('Service Status')),
				E('div', {id:'sm-status-section'}, [self._renderStatus(status)]),
				E('div', {id:'sm-actions-section'}, [self._renderActions(status)])
			]),

			E('div', {class:'cbi-section'}, [
				E('h3', {}, _('Health Checks')),
				E('div', {id:'sm-diag-section'}, [self._renderDiagnostics(diag)])
			]),

			E('div', {class:'cbi-section'}, [
				E('h3', {}, _('Dashboard')),
				E('div', {id:'sm-dashboard-section'}, [self._renderDashboardSection(status)])
			])
		]));
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
