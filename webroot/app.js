/**
 * @author  bomo
 * @description 微信保推送 WebUI - 前端逻辑
 * 使用 Magisk/KernelSU/APatch JS 桥接直接执行 shell 命令，
 * 而非 CGI fetch 方式，确保跨平台兼容。
 */

var MODDIR = '/data/adb/modules/wechat_push_keeper'
var LOG_FILE = '/data/local/tmp/wechat_push_keeper.log'
var ACTION = MODDIR + '/action.sh'
var cbCounter = 0
var defaultValues = {}

function $(sel) { return document.querySelector(sel) }
function $$(sel) { return document.querySelectorAll(sel) }

/**
 * 跨平台 shell 执行桥接
 * 依次尝试 KernelSU(ksu) → APatch(apd) → APatch旧版(ap) → Magisk($)
 * @param {string} cmd - 要执行的 shell 命令
 * @param {number} timeout - 超时毫秒数
 * @returns {Promise<{errno:number, stdout:string, stderr:string}>}
 */
function kexec(cmd, timeout) {
  timeout = timeout || 10000

  if (typeof ksu !== 'undefined' && ksu.exec) {
    return new Promise(function(resolve) {
      var cbName = 'cb_' + Date.now() + '_' + (++cbCounter)
      var timer = setTimeout(function() { delete window[cbName]; resolve({errno: -1, stdout: '', stderr: 'timeout'}) }, timeout)
      window[cbName] = function(errno, stdout, stderr) {
        clearTimeout(timer)
        delete window[cbName]
        resolve({errno: Number(errno), stdout: stdout || '', stderr: stderr || ''})
      }
      try { ksu.exec(cmd, '{}', cbName) } catch(e) { clearTimeout(timer); delete window[cbName]; resolve({errno: -1, stdout: '', stderr: String(e)}) }
    })
  }

  if (typeof apd !== 'undefined' && apd.exec) {
    return new Promise(function(resolve) {
      var cbName = 'cb_' + Date.now() + '_' + (++cbCounter)
      var timer = setTimeout(function() { delete window[cbName]; resolve({errno: -1, stdout: '', stderr: 'timeout'}) }, timeout)
      window[cbName] = function(errno, stdout, stderr) {
        clearTimeout(timer)
        delete window[cbName]
        resolve({errno: Number(errno), stdout: stdout || '', stderr: stderr || ''})
      }
      try { apd.exec(cmd, '{}', cbName) } catch(e) { clearTimeout(timer); delete window[cbName]; resolve({errno: -1, stdout: '', stderr: String(e)}) }
    })
  }

  if (typeof ap !== 'undefined' && ap.exec) {
    return new Promise(function(resolve) {
      var cbName = 'cb_' + Date.now() + '_' + (++cbCounter)
      var timer = setTimeout(function() { delete window[cbName]; resolve({errno: -1, stdout: '', stderr: 'timeout'}) }, timeout)
      window[cbName] = function(errno, stdout, stderr) {
        clearTimeout(timer)
        delete window[cbName]
        resolve({errno: Number(errno), stdout: stdout || '', stderr: stderr || ''})
      }
      try { ap.exec(cmd, '{}', cbName) } catch(e) { clearTimeout(timer); delete window[cbName]; resolve({errno: -1, stdout: '', stderr: String(e)}) }
    })
  }

  if (typeof $ !== 'undefined' && $.exec) {
    return new Promise(function(resolve) {
      var cbName = 'cb_' + Date.now() + '_' + (++cbCounter)
      var timer = setTimeout(function() { delete window[cbName]; resolve({errno: -1, stdout: '', stderr: 'timeout'}) }, timeout)
      window[cbName] = function(errno, stdout, stderr) {
        clearTimeout(timer)
        delete window[cbName]
        resolve({errno: Number(errno), stdout: stdout || '', stderr: stderr || ''})
      }
      try { $.exec(cmd, '{}', cbName) } catch(e) { clearTimeout(timer); delete window[cbName]; resolve({errno: -1, stdout: '', stderr: String(e)}) }
    })
  }

  return Promise.resolve({errno: -1, stdout: '', stderr: 'no bridge available'})
}

/** 执行 shell 命令并返回 stdout 字符串 */
function kexecOut(cmd, timeout) {
  return kexec(cmd, timeout).then(function(r) { return r.stdout || '' })
}

/** 执行 shell 命令并解析 JSON 返回 */
function kexecJSON(cmd, timeout) {
  return kexecOut(cmd, timeout).then(function(out) {
    try { return JSON.parse(out.trim()) } catch(e) { return null }
  })
}

function showToast(msg) {
  var t = $('#toast')
  if (!t) return
  t.textContent = msg
  t.classList.add('show')
  clearTimeout(t._hide)
  t._hide = setTimeout(function() { t.classList.remove('show') }, 2500)
}

/** 更新运行状态面板 */
function updateStatus(data) {
  if (!data) return
  var elMain = $('#sv-main')
  if (elMain) { elMain.textContent = data.running ? '运行中' : '已停止'; elMain.className = 'status-value ' + (data.running ? 'running' : 'stopped') }
  var elScreen = $('#sv-screen')
  if (elScreen) { elScreen.textContent = data.screen_running ? '运行中' : '已停止'; elScreen.className = 'status-value ' + (data.screen_running ? 'running' : 'stopped') }
  var elVoip = $('#sv-voip')
  if (elVoip) { elVoip.textContent = data.voip_running ? '运行中' : '已停止'; elVoip.className = 'status-value ' + (data.voip_running ? 'running' : 'stopped') }
  var elPid = $('#sv-pid span')
  if (elPid) elPid.textContent = data.pid ? 'PID: ' + data.pid : '-'
  var elSize = $('#sv-logsize span')
  if (elSize) elSize.textContent = formatSize(data.log_size)
}

function formatSize(bytes) {
  if (!bytes) return '0 B'
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB'
  return (bytes / 1048576).toFixed(1) + ' MB'
}

/** 填充配置表单 */
function fillConfig(data) {
  if (!data) return
  $('#cfg-kill-delay').value = data.kill_delay
  $('#cfg-screen-first-kill-delay').value = data.screen_first_kill_delay
  $('#cfg-screen-kill-delay').value = data.screen_kill_delay
  $('#cfg-screen-poll').value = data.screen_poll_interval
  $('#cfg-voip-poll').value = data.voip_poll_interval
  $('#cfg-log-lines').value = data.log_max_lines

  defaultValues = {
    kill_delay: data.default_kill_delay,
    screen_first_kill_delay: data.default_screen_first_kill_delay,
    screen_kill_delay: data.default_screen_kill_delay,
    screen_poll_interval: data.default_screen_poll_interval,
    voip_poll_interval: data.default_voip_poll_interval,
    log_max_lines: data.default_log_max_lines
  }
  showDefaultBadges()
}

/** 更新"默认"标记的显隐 */
function showDefaultBadges() {
  var map = {
    'cfg-kill-delay': 'kill_delay',
    'cfg-screen-first-kill-delay': 'screen_first_kill_delay',
    'cfg-screen-kill-delay': 'screen_kill_delay',
    'cfg-screen-poll': 'screen_poll_interval',
    'cfg-voip-poll': 'voip_poll_interval',
    'cfg-log-lines': 'log_max_lines'
  }
  for (var id in map) {
    if (!map.hasOwnProperty(id)) continue
    var el = document.getElementById(id)
    if (!el) continue
    var badge = el.parentElement.parentElement.querySelector('.default-badge')
    if (!badge) continue
    var val = parseInt(el.value)
    badge.style.display = (!isNaN(val) && val === defaultValues[map[id]]) ? 'inline' : 'none'
  }
}

/** 读取日志文件并展示 */
function loadLog() {
  var container = $('#log-content')
  if (!container) return
  container.textContent = '加载中...'
  // 直接读取日志文件（不经过 action.sh，减少一次 shell 调用）
  kexecOut('tail -n 200 "' + LOG_FILE + '" 2>/dev/null').then(function(text) {
    if (!text || !text.trim()) {
      container.textContent = '(日志为空)'
      return
    }
    container.textContent = text
    container.scrollTop = container.scrollHeight
  })
}

/** 加载全部数据：状态 + 配置 + 日志 */
async function loadAll() {
  var loadingEl = $('#loading')
  var mainEl = $('#main-content')
  if (loadingEl) loadingEl.style.display = 'block'
  if (mainEl) mainEl.style.display = 'none'

  var actionPath = 'sh "' + ACTION + '"'
  var statusData = await kexecJSON(actionPath + ' status')
  var configData = await kexecJSON(actionPath + ' config')

  if (loadingEl) loadingEl.style.display = 'none'
  if (mainEl) mainEl.style.display = 'block'

  updateStatus(statusData)
  fillConfig(configData)
  loadLog()
}

/** 收集表单中的配置值 */
function getConfigValues() {
  return {
    kill_delay: parseInt($('#cfg-kill-delay').value) || 5,
    screen_first_kill_delay: parseInt($('#cfg-screen-first-kill-delay').value) || 0,
    screen_kill_delay: parseInt($('#cfg-screen-kill-delay').value) || 3,
    screen_poll_interval: parseInt($('#cfg-screen-poll').value) || 2,
    voip_poll_interval: parseInt($('#cfg-voip-poll').value) || 20,
    log_max_lines: parseInt($('#cfg-log-lines').value) || 100
  }
}

/** 保存配置并重启服务 */
async function saveConfig() {
  var v = getConfigValues()

  // 校验：第二次清理时间不允许小于第一次清理时间
  if (v.screen_kill_delay < v.screen_first_kill_delay) {
    showToast('灭屏二次延迟不能小于灭屏第一次延迟，请调整后再保存')
    var el = $('#cfg-screen-kill-delay')
    if (el) el.focus()
    return
  }

  var cmd = 'sh "' + ACTION + '" save ' + v.kill_delay + ' ' + v.screen_first_kill_delay + ' ' + v.screen_kill_delay + ' ' + v.screen_poll_interval + ' ' + v.voip_poll_interval + ' ' + v.log_max_lines
  var result = await kexecJSON(cmd)
  if (result) {
    showToast('配置已保存并生效')
    updateStatus(result)
    showDefaultBadges()
  } else {
    showToast('保存失败，请检查模块是否正常安装')
  }
}

/** 恢复默认配置 */
async function resetDefaults() {
  var result = await kexecJSON('sh "' + ACTION + '" default')
  if (result) {
    showToast('已恢复默认配置并生效')
    loadAll()
  } else {
    showToast('恢复失败')
  }
}

/** 重启服务 */
async function restartService() {
  var result = await kexecJSON('sh "' + ACTION + '" restart')
  if (result) {
    showToast('服务已重启')
    updateStatus(result)
  }
}

// 页面初始化
document.addEventListener('DOMContentLoaded', function() {
  loadAll()

  var btnSave = $('#btn-save')
  if (btnSave) btnSave.addEventListener('click', saveConfig)
  var btnDefault = $('#btn-default')
  if (btnDefault) btnDefault.addEventListener('click', resetDefaults)
  var btnRestart = $('#btn-restart')
  if (btnRestart) btnRestart.addEventListener('click', restartService)
  var btnRefreshLog = $('#btn-refresh-log')
  if (btnRefreshLog) btnRefreshLog.addEventListener('click', loadLog)
  var btnRefreshStatus = $('#btn-refresh-status')
  if (btnRefreshStatus) btnRefreshStatus.addEventListener('click', loadAll)

  // 输入值变化时更新默认标记
  $$('.config-input').forEach(function(el) {
    el.addEventListener('input', showDefaultBadges)
    el.addEventListener('change', showDefaultBadges)
  })

  // 日志自动滚动
  var logContainer = $('#log-content')
  if (logContainer) {
    logContainer.addEventListener('DOMSubtreeModified', function() {
      logContainer.scrollTop = logContainer.scrollHeight
    })
  }
})