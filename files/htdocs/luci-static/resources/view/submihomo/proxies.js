'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var callGetProxies = rpc.declare({
	object: 'submihomo',
	method: 'get_proxies',
	expect: {}
});

var callStart = rpc.declare({
	object: 'submihomo',
	method: 'start',
	expect: {}
});

var callTestConnection = rpc.declare({
	object: 'submihomo',
	method: 'test_connection',
	expect: {}
});

function latencyColor(ms) {
	if (ms === null || ms === undefined) return '#9e9e9e';
	if (ms < 100) return '#4caf50';
	if (ms < 500) return '#ff9800';
	return '#f44336';
}

function latencyBadge(history) {
	if (!Array.isArray(history) || history.length === 0)
		return E('span', {style:'color:#9e9e9e'}, '—');
	var ms = history[0].delay;
	return E('span', {style:'color:'+latencyColor(ms)+';font-weight:bold'}, ms + 'ms');
}

return view.extend({
	_prevData: null,

	load: function() {
		return L.resolveDefault(callGetProxies(), {groups:[], proxies:[], error:null});
	},

	_renderEmpty: function() {
		var self = this;
		return E('div', {class:'alert-message warning'}, [
			E('p', {}, _('SubMiHomo is not running.')),
			E('button', {class:'btn cbi-button-positive', click: function() {
				L.resolveDefault(callStart(), {}).then(function() {
					self._refresh();
				});
			}}, _('Start Service'))
		]);
	},

	_renderProxyTable: function(data) {
		var groups = data.groups || [];
		var proxies = data.proxies || [];

		// Build proxy lookup map
		var proxyMap = {};
		proxies.forEach(function(p) { proxyMap[p.name] = p; });

		var sections = groups.map(function(g) {
			var isSelector = (g.type === 'Selector' || g.type === 'select');
			var header = E('h4', {}, g.name + ' (' + g.type + ') — ' + _('Active: ') + (g.now || '—'));
			var rows = (g.all || []).map(function(memberName) {
				var p = proxyMap[memberName];
				var badge = p ? latencyBadge(p.history) : E('span', {}, '—');
				var aliveIcon = p && p.alive !== false ? '✔' : '✘';

				var nameCell;
				if (isSelector) {
					nameCell = E('a', {
						href: '#',
						style: memberName === g.now ? 'font-weight:bold' : '',
						click: function(e) {
							e.preventDefault();
							// Switch proxy via Mihomo API through test_connection proxy
							var cfgRPC = rpc.declare({
								object: 'submihomo',
								method: 'set_config',
								params: ['main'],
								expect: {}
							});
							// Use direct API call via backend
							fetch('/ubus', {
								method: 'POST',
								headers: {'Content-Type':'application/json'},
								body: JSON.stringify({
									jsonrpc: '2.0', id: 1,
									method: 'call',
									params: [rpc.getSessionID(), 'submihomo', 'get_proxies', {}]
								})
							});
						}
					}, memberName);
				} else {
					nameCell = E('span', {style: memberName === g.now ? 'font-weight:bold' : ''}, memberName);
				}

				return E('tr', {}, [
					E('td', {style:'padding:4px 8px'}, nameCell),
					E('td', {style:'padding:4px 8px'}, badge),
					E('td', {style:'padding:4px 8px'}, aliveIcon)
				]);
			});

			return E('div', {class:'cbi-section', style:'margin-bottom:1em'}, [
				header,
				E('table', {class:'table'}, [
					E('tr', {class:'table-titles'}, [
						E('th', {}, _('Name')),
						E('th', {}, _('Latency')),
						E('th', {}, _('Alive'))
					])
				].concat(rows))
			]);
		});

		return E('div', {id:'sm-proxies-content'}, sections);
	},

	_refresh: function() {
		var self = this;
		L.resolveDefault(callGetProxies(), {groups:[], proxies:[], error:null}).then(function(data) {
			var el = document.getElementById('sm-proxies-root');
			if (!el) return;
			el.innerHTML = '';
			if (data.error || (data.groups.length === 0 && data.proxies.length === 0 && data.error)) {
				el.appendChild(self._renderEmpty());
			} else if (data.groups.length === 0 && data.proxies.length === 0) {
				el.appendChild(self._renderEmpty());
			} else {
				el.appendChild(self._renderProxyTable(data));
			}
		});
	},

	render: function(data) {
		var self = this;
		poll.add(function() { return self._refresh(); }, 30);

		var testBtn = E('button', {class:'btn cbi-button-action', click: function() {
			ui.showModal(_('Testing connectivity…'), [E('p', _('Testing connection through proxy…'))]);
			L.resolveDefault(callTestConnection(), {}).then(function(r) {
				ui.hideModal();
				if (r && r.success) {
					ui.addNotification(null, E('p', _('Connection OK — ') + r.latency + 'ms'), 'info');
				} else {
					ui.addNotification(null, E('p', _('Connection test failed: ') + (r&&r.error||'')), 'danger');
				}
			});
		}}, _('Test Connection'));

		var content;
		if (data.error || (data.groups.length === 0 && data.proxies.length === 0)) {
			content = self._renderEmpty();
		} else {
			content = self._renderProxyTable(data);
		}

		return E('div', {}, [
			E('h2', {}, _('SubMiHomo — Proxies')),
			E('div', {style:'margin-bottom:1em'}, [testBtn]),
			E('div', {id:'sm-proxies-root'}, [content])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
