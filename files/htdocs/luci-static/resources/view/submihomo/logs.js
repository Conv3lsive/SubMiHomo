'use strict';
'require view';
'require rpc';
'require poll';

var callGetLogs = rpc.declare({
	object: 'submihomo',
	method: 'get_logs',
	params: ['lines', 'source'],
	expect: {}
});

return view.extend({
	_autoRefresh: false,
	_pollHandle: null,

	load: function() {
		return L.resolveDefault(callGetLogs(100, 'all'), {lines:[]});
	},

	_updateLogs: function(lines) {
		var ta = document.getElementById('sm-log-textarea');
		if (!ta) return;
		var atBottom = ta.scrollTop + ta.clientHeight >= ta.scrollHeight - 10;
		ta.value = (lines || []).join('\n');
		if (atBottom) ta.scrollTop = ta.scrollHeight;
	},

	_fetch: function() {
		var self = this;
		var linesSel = document.getElementById('sm-log-lines');
		var sourceSel = document.getElementById('sm-log-source');
		var n = linesSel ? parseInt(linesSel.value) : 100;
		var src = sourceSel ? sourceSel.value : 'all';
		return L.resolveDefault(callGetLogs(n, src), {lines:[]}).then(function(r) {
			self._updateLogs(r.lines);
		});
	},

	render: function(data) {
		var self = this;

		var linesSel = E('select', {id:'sm-log-lines', change: function() { self._fetch(); }}, [
			E('option', {value:'50'},  '50'),
			E('option', {value:'100', selected:'selected'}, '100'),
			E('option', {value:'200'}, '200'),
			E('option', {value:'500'}, '500')
		]);

		var sourceSel = E('select', {id:'sm-log-source', change: function() { self._fetch(); }}, [
			E('option', {value:'all',     selected:'selected'}, _('All')),
			E('option', {value:'service'}, _('Service only')),
			E('option', {value:'mihomo'},  _('Mihomo only'))
		]);

		var refreshBtn = E('button', {class:'btn cbi-button-action', click: function() {
			self._fetch();
		}}, _('↺ Refresh'));

		var autoChk = E('input', {type:'checkbox', id:'sm-auto-refresh', change: function() {
			self._autoRefresh = this.checked;
			if (self._autoRefresh) {
				self._pollHandle = poll.add(function() { return self._fetch(); }, 5);
			} else if (self._pollHandle) {
				poll.remove(self._pollHandle);
				self._pollHandle = null;
			}
		}});

		var clearBtn = E('button', {class:'btn cbi-button-neutral', click: function() {
			var ta = document.getElementById('sm-log-textarea');
			if (ta) ta.value = '';
		}}, _('Clear Display'));

		var downloadBtn = E('button', {class:'btn cbi-button-neutral', click: function() {
			var ta = document.getElementById('sm-log-textarea');
			if (!ta) return;
			var blob = new Blob([ta.value], {type:'text/plain'});
			var a = document.createElement('a');
			a.href = URL.createObjectURL(blob);
			a.download = 'submihomo.log';
			a.click();
			URL.revokeObjectURL(a.href);
		}}, _('Download .log'));

		var ta = E('textarea', {
			id: 'sm-log-textarea',
			readonly: 'readonly',
			style: 'width:100%;height:500px;font-family:monospace;font-size:12px;white-space:pre;overflow-x:scroll'
		}, (data.lines || []).join('\n'));

		var filterInput = E('input', {
			type: 'text',
			id: 'sm-log-filter',
			placeholder: _('Filter (client-side)…'),
			style: 'width:300px',
			input: function() {
				var ta = document.getElementById('sm-log-textarea');
				if (!ta) return;
				var needle = this.value.toLowerCase();
				var lines = ta.value.split('\n');
				if (!needle) return;
				ta.value = lines.filter(function(l) {
					return l.toLowerCase().indexOf(needle) !== -1;
				}).join('\n');
			}
		});

		return E('div', {}, [
			E('h2', {}, _('SubMiHomo — Logs')),
			E('div', {class:'cbi-section'}, [
				E('div', {style:'display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-bottom:8px'}, [
					E('label', {}, _('Source: ')), sourceSel,
					E('label', {}, _('Lines: ')), linesSel,
					refreshBtn,
					E('label', {}, [autoChk, ' ', _('Auto-refresh (5s)')]),
					filterInput
				]),
				ta,
				E('div', {style:'margin-top:8px;display:flex;gap:8px'}, [clearBtn, downloadBtn])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
