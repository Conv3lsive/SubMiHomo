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

var callUpdateSubscription = rpc.declare({
	object: 'submihomo',
	method: 'update_subscription',
	expect: {}
});

return view.extend({
	load: function() {
		return L.resolveDefault(callGetConfig(), {main:{},bypass:{address:[]}});
	},

	render: function(cfg) {
		var self = this;
		var main = (cfg && cfg.main) ? cfg.main : {};
		var url = main.subscription_url || '';
		var interval = main.subscription_update_interval || '24';

		var urlField = E('input', {
			type: 'text',
			id: 'sm-sub-url',
			value: url,
			placeholder: 'https://provider.example.com/sub/...',
			style: 'width:100%;font-family:monospace'
		});

		var intervalSel = E('select', {id:'sm-sub-interval'}, [
			E('option', {value:'0',  selected: interval==='0'  ?'selected':null}, _('Disabled')),
			E('option', {value:'6',  selected: interval==='6'  ?'selected':null}, _('Every 6 hours')),
			E('option', {value:'12', selected: interval==='12' ?'selected':null}, _('Every 12 hours')),
			E('option', {value:'24', selected: interval==='24' ?'selected':null}, _('Every 24 hours')),
			E('option', {value:'48', selected: interval==='48' ?'selected':null}, _('Every 48 hours')),
			E('option', {value:'72', selected: interval==='72' ?'selected':null}, _('Every 72 hours'))
		]);

		var errBanner = E('div', {id:'sm-sub-error', style:'display:none', class:'alert-message danger'});

		function doSaveAndUpdate() {
			var newUrl = document.getElementById('sm-sub-url').value.trim();
			var newInterval = document.getElementById('sm-sub-interval').value;
			var errEl = document.getElementById('sm-sub-error');

			// Client-side validation
			if (newUrl !== '' && !newUrl.match(/^https:\/\//)) {
				errEl.textContent = _('Subscription URL must use HTTPS (begin with https://)');
				errEl.style.display = '';
				return;
			}
			errEl.style.display = 'none';

			var payload = {
				main: {
					subscription_url: newUrl,
					subscription_update_interval: newInterval
				}
			};

			L.resolveDefault(callSetConfig(payload.main, payload.bypass), {}).then(function(r) {
				if (r && r.success === false) {
					errEl.textContent = (r.errors || [r.error || _('Save failed')]).join('; ');
					errEl.style.display = '';
					return;
				}
				// Trigger subscription update
				ui.showModal(_('Downloading Subscription'), [
					E('p', _('Downloading and validating subscription, please wait…'))
				]);
				L.resolveDefault(callUpdateSubscription(), {}).then(function(u) {
					ui.hideModal();
					if (u && u.success === false) {
						errEl.textContent = _('Update failed: ') + (u.error || _('unknown error'));
						errEl.style.display = '';
					} else {
						ui.addNotification(null,
							E('p', _('Subscription updated — ') + ((u&&u.proxy_count)||0) + _(' proxies loaded')),
							'info');
					}
				});
			});
		}

		function doUpdateNow() {
			var errEl = document.getElementById('sm-sub-error');
			errEl.style.display = 'none';
			ui.showModal(_('Downloading Subscription'), [
				E('p', _('Downloading and validating subscription, please wait…'))
			]);
			L.resolveDefault(callUpdateSubscription(), {}).then(function(u) {
				ui.hideModal();
				if (u && u.success === false) {
					errEl.textContent = _('Update failed: ') + (u.error || _('unknown error'));
					errEl.style.display = '';
				} else {
					ui.addNotification(null,
						E('p', _('Subscription updated — ') + ((u&&u.proxy_count)||0) + _(' proxies loaded')),
						'info');
				}
			});
		}

		return E('div', {}, [
			E('h2', {}, _('SubMiHomo — Subscription')),
			E('div', {class:'cbi-section'}, [
				E('h3', {}, _('Subscription URL')),
				errBanner,
				E('p', {}, urlField),
				E('p', {style:'color:#888;font-size:0.9em'}, _('Must begin with https://')),

				E('div', {class:'cbi-value'}, [
					E('label', {}, _('Update interval: ')),
					intervalSel
				]),

				E('div', {class:'cbi-section-node',style:'margin-top:1em'}, [
					E('button', {class:'btn cbi-button-positive', click: doSaveAndUpdate},
						_('Save & Update Now')),
					' ',
					E('button', {class:'btn cbi-button-action', click: doUpdateNow},
						_('Update Now'))
				])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
