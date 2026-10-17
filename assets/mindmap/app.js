// SimpleMindMap 0.14.0 (MIT), vendored at ./vendor.
// https://github.com/wanglin2/mind-map
import MindMap from './vendor/simpleMindMap.esm.min.js'

const VIRTUAL_ROOT_ID = 'daymark:root'
const NEW_PREFIX = 'new:'

// The page only needs dragging and node activation from the library. Keeping
// the plugin list minimal avoids rich-text, export and collaboration code
// paths that this feature never exposes.
MindMap.pluginList = MindMap.pluginList.filter(plugin =>
  ['drag'].includes(plugin.instanceName)
)

const container = document.getElementById('map')
const status = document.getElementById('status')

const menu = document.createElement('div')
menu.className = 'dm-menu'
menu.setAttribute('role', 'menu')
menu.hidden = true
document.body.appendChild(menu)

let mindMap = null
let ready = false
let currentRootId = ''
let emitTimer = 0
let lastTree = ''
let lastSelection = ''
let lastUndo = null
let lastRedo = null

// Nodes created here use a temporary id until the host saves the tree. Keep
// the assignment so the same node never changes identity while this page lives.
const assignedIds = new Map()

function post(message) {
  try {
    window.chrome?.webview?.postMessage(message)
  } catch (error) {
    console.error(error)
  }
}

function fail(message) {
  if (status) {
    status.hidden = false
    status.textContent = message
  }
  post({ type: 'error', message })
}

function idOf(node) {
  const data = node.getData()
  const id = data._daymarkId || NEW_PREFIX + data.uid
  return assignedIds.get(id) || id
}

function textOf(node) {
  const text = node.getData('text')
  return typeof text === 'string' ? text : ''
}

function describe(node) {
  if (!node) return null
  return {
    id: idOf(node),
    name: textOf(node),
    isRoot: !!node.isRoot,
    childCount: (node.children || []).length
  }
}



function selectedNode() {
  const list = mindMap?.renderer?.activeNodeList || []
  return list.find(node => !node.isGeneralization) || null
}

function serializeNode(node) {
  return {
    id: idOf(node),
    name: textOf(node),
    children: (node.children || []).map(serializeNode)
  }
}

function serializeTree() {
  const root = mindMap?.renderer?.root
  if (!root) return null
  return {
    id: idOf(root),
    name: textOf(root),
    children: (root.children || []).map(serializeNode)
  }
}

function walk(node, visit) {
  if (!node) return false
  if (visit(node)) return true
  for (const child of node.children || []) {
    if (walk(child, visit)) return true
  }
  return false
}

function findNode(id) {
  if (!mindMap || !id) return null
  const root = mindMap.renderer.root
  if (id === idOf(root)) return root
  if (id.startsWith(NEW_PREFIX)) {
    return mindMap.renderer.findNodeByUid?.(id.slice(NEW_PREFIX.length)) || null
  }
  let found = null
  walk(root, node => {
    if (idOf(node) === id) {
      found = node
      return true
    }
    return false
  })
  return found
}

function canUndo() {
  return !!mindMap && mindMap.command.activeHistoryIndex > 0
}

function canRedo() {
  return (
    !!mindMap &&
    mindMap.command.activeHistoryIndex < mindMap.command.history.length - 1
  )
}

function emitNow() {
  if (!mindMap || !ready) return
  const tree = serializeTree()
  if (!tree) return
  const selection = describe(selectedNode())
  const treeText = JSON.stringify(tree)
  const selectionText = JSON.stringify(selection)
  const undo = canUndo()
  const redo = canRedo()
  if (
    treeText === lastTree &&
    selectionText === lastSelection &&
    undo === lastUndo &&
    redo === lastRedo
  ) {
    return
  }
  lastTree = treeText
  lastSelection = selectionText
  lastUndo = undo
  lastRedo = redo
  post({
    type: 'change',
    tree,
    selection,
    canUndo: undo,
    canRedo: redo
  })
}

function scheduleEmit() {
  clearTimeout(emitTimer)
  emitTimer = setTimeout(emitNow, 40)
}

function hideMenu() {
  menu.hidden = true
  menu.textContent = ''
}

function showMenu(event, node) {
  if (!node) {
    hideMenu()
    return
  }
  const id = idOf(node)
  const items = []
  if (
    currentRootId &&
    currentRootId !== VIRTUAL_ROOT_ID &&
    id === currentRootId
  ) {
    items.push({ label: '返回 Daymark', target: '' })
  } else if (id !== VIRTUAL_ROOT_ID && id !== currentRootId) {
    items.push({ label: '进入', target: id })
  }
  if (!items.length) {
    hideMenu()
    return
  }
  menu.textContent = ''
  items.forEach(item => {
    const button = document.createElement('button')
    button.type = 'button'
    button.setAttribute('role', 'menuitem')
    button.textContent = item.label
    button.addEventListener('click', () => {
      hideMenu()
      post({ type: 'enter', id: item.target })
    })
    menu.appendChild(button)
  })
  menu.hidden = false
  const rect = menu.getBoundingClientRect()
  const x = event.clientX || 0
  const y = event.clientY || 0
  menu.style.left =
    Math.max(8, Math.min(x, window.innerWidth - rect.width - 8)) + 'px'
  menu.style.top =
    Math.max(8, Math.min(y, window.innerHeight - rect.height - 8)) + 'px'
}

function toNodeData(node) {
  const data = { text: node.name, expand: true }
  if (node.id && !node.id.startsWith(NEW_PREFIX)) {
    data._daymarkId = node.id
  }
  return {
    data,
    children: (node.children || []).map(toNodeData)
  }
}

function applyMenuColors(colors) {
  const root = document.documentElement.style
  root.setProperty('--dm-menu-bg', colors.surface)
  root.setProperty('--dm-menu-text', colors.text)
  root.setProperty('--dm-menu-border', colors.border)
  root.setProperty('--dm-menu-hover', colors.hover)
  root.setProperty('--dm-menu-font', colors.fontFamily)
}

function buildThemeConfig(colors) {
  return {
    backgroundColor: colors.background,
    lineColor: colors.line,
    lineWidth: 1.5,
    lineStyle: 'curve',
    rootLineKeepSameInCurve: true,
    rootLineStartPositionKeepSameInCurve: true,
    hoverRectColor: colors.hover,
    hoverRectPadding: 3,
    root: {
      shape: 'rectangle',
      fillColor: colors.accent,
      color: colors.onAccent,
      borderColor: 'transparent',
      borderWidth: 0,
      borderRadius: 10,
      fontSize: 15,
      fontWeight: 'bold',
      paddingX: 18,
      paddingY: 9,
      fontFamily: colors.fontFamily,
      textAlign: 'left'
    },
    second: {
      shape: 'rectangle',
      fillColor: colors.surface,
      color: colors.text,
      borderColor: colors.border,
      borderWidth: 1,
      borderRadius: 10,
      fontSize: 15,
      fontWeight: 'normal',
      paddingX: 16,
      paddingY: 8,
      marginX: 80,
      marginY: 22,
      fontFamily: colors.fontFamily,
      textAlign: 'left'
    },
    node: {
      shape: 'rectangle',
      fillColor: colors.surface,
      color: colors.text,
      borderColor: colors.border,
      borderWidth: 1,
      borderRadius: 8,
      fontSize: 14,
      fontWeight: 'normal',
      paddingX: 12,
      paddingY: 6,
      marginX: 52,
      marginY: 10,
      fontFamily: colors.fontFamily,
      textAlign: 'left'
    }
  }
}

function createMap(payload) {
  const root = payload.tree
  const data = {
    data: { text: root.name, _daymarkId: root.id, expand: true },
    children: (root.children || []).map(toNodeData)
  }
  mindMap = new MindMap({
    el: container,
    data,
    layout: 'logicalStructure',
    theme: 'default',
    themeConfig: buildThemeConfig(payload.colors),
    readonly: false,
    fit: true,
    fitPadding: 88,
    mousewheelAction: 'move',
    mousewheelMoveStep: 120,
    alwaysShowExpandBtn: true,
    enableCtrlKeyNodeSelection: false,
    isDisableDrag: false,
    enableFreeDrag: false,
    beforeTextEdit: node =>
      !(node && node.isRoot && idOf(node) === VIRTUAL_ROOT_ID),
    defaultInsertSecondLevelNodeText: '新标签',
    defaultInsertBelowSecondLevelNodeText: '新标签',
    expandBtnStyle: {
      color: payload.colors.muted,
      fill: payload.colors.surface
    },
    errorHandler: (type, error) => {
      console.error(type, error)
      post({
        type: 'error',
        message: (error && (error.message || String(error))) || String(type)
      })
    }
  })

  // Keep the mind-map keyboard flow (Tab/Enter create and edit in place) but
  // drop destructive defaults such as Del without confirmation.
  const keys = mindMap.keyCommand
  keys.shortcutMap = {}
  keys.addShortcut('Tab', () => {
    const parent = selectedNode() || mindMap.renderer.root
    if (!parent) return
    addChild(idOf(parent), uniqueChildName(parent))
  })
  keys.addShortcut('Enter', () => {
    const node = selectedNode()
    if (!node || node.isRoot || !node.parent) return
    mindMap.execCommand('INSERT_NODE', true, [node], {
      text: uniqueChildName(node.parent),
      _daymarkId: ''
    })
  })
  keys.addShortcut('F2', () => {
    const node = selectedNode()
    if (node) beginEdit(idOf(node))
  })
  keys.addShortcut('Control+z', undo)
  keys.addShortcut('Control+y', redo)
  keys.addShortcut('Control+Shift+z', redo)
  keys.addShortcut('Control+s', () => post({ type: 'save' }))
  keys.addShortcut('Del', () => post({ type: 'delete' }))

  mindMap.on('data_change', scheduleEmit)
  mindMap.on('back_forward', scheduleEmit)
  mindMap.on('node_active', scheduleEmit)
  mindMap.on('node_tree_render_end', scheduleEmit)
  mindMap.on('node_contextmenu', showMenu)
  mindMap.on('contextmenu', hideMenu)
  mindMap.on('node_click', hideMenu)
  mindMap.on('draw_click', hideMenu)
}

function load(payload) {
  if (!payload || !payload.tree || !payload.colors) {
    fail('导图数据不完整。')
    return
  }
  const root = payload.tree
  applyMenuColors(payload.colors)
  currentRootId = root.id
  hideMenu()
  const data = {
    data: { text: root.name, _daymarkId: root.id, expand: true },
    children: (root.children || []).map(toNodeData)
  }
  if (!mindMap) {
    createMap(payload)
  } else {
    const view = mindMap.view.getTransformData()
    mindMap.setData(data)
    if (view) mindMap.view.setTransformData(view)
    mindMap.setThemeConfig(buildThemeConfig(payload.colors))
  }
  ready = true
  if (status) status.hidden = true
  lastTree = ''
  lastSelection = ''
  lastUndo = null
  lastRedo = null
  if (payload.fit) {
    setTimeout(() => mindMap?.view.fit(), 200)
  }
  scheduleEmit()
}

function setColors(colors) {
  if (!colors || !mindMap) return
  applyMenuColors(colors)
  mindMap.setThemeConfig(buildThemeConfig(colors))
  scheduleEmit()
}

function setAssignedIds(ids) {
  if (!ids) return
  Object.entries(ids).forEach(([temporary, stable]) => {
    if (
      typeof temporary === 'string' &&
      typeof stable === 'string' &&
      temporary &&
      stable
    ) {
      assignedIds.set(temporary, stable)
    }
  })
  scheduleEmit()
}



function uniqueChildName(parent) {
  const used = new Set(
    (parent.children || []).map(child => textOf(child).trim())
  )
  let name = '新标签'
  let index = 1
  while (used.has(name)) {
    index++
    name = '新标签 ' + index
  }
  return name
}

function addChild(parentId, name) {
  if (!mindMap) return
  const parent = findNode(parentId) || mindMap.renderer.root
  mindMap.execCommand('INSERT_CHILD_NODE', true, [parent], {
    text: name,
    _daymarkId: ''
  })
}

function beginEdit(id) {
  const node = findNode(id)
  if (!node) return
  if (node.isRoot && idOf(node) === VIRTUAL_ROOT_ID) return
  mindMap.renderer.textEdit.show({ node })
}

function endEdit() {
  const edit = mindMap?.renderer?.textEdit
  if (edit?.isShowTextEdit()) edit.hideEditTextBox()
}

function remove(id) {
  const node = findNode(id)
  if (!node || node.isRoot) return
  mindMap.execCommand('REMOVE_NODE', [node])
  scheduleEmit()
}

function undo() {
  if (!mindMap || !canUndo()) return
  mindMap.execCommand('BACK')
  scheduleEmit()
}

function redo() {
  if (!mindMap || !canRedo()) return
  mindMap.execCommand('FORWARD')
  scheduleEmit()
}

function zoomIn() {
  mindMap?.view.enlarge()
}

function zoomOut() {
  mindMap?.view.narrow()
}

function fit() {
  mindMap?.view.fit()
}

function expandAll() {
  mindMap?.execCommand('EXPAND_ALL')
}

function collapseAll() {
  mindMap?.execCommand('UNEXPAND_ALL')
}

window.Daymark = {
  load,
  setColors,
  setAssignedIds,
  addChild,
  beginEdit,
  endEdit,
  remove,
  undo,
  redo,
  zoomIn,
  zoomOut,
  fit,
  expandAll,
  collapseAll
}

document.addEventListener('contextmenu', event => event.preventDefault())
document.addEventListener('dragover', event => event.preventDefault())
document.addEventListener('drop', event => event.preventDefault())
document.addEventListener(
  'mousedown',
  event => {
    if (!menu.contains(event.target)) hideMenu()
  },
  true
)
document.addEventListener('keydown', event => {
  if (event.key === 'Escape') hideMenu()
})
window.addEventListener('blur', hideMenu)
window.addEventListener('resize', hideMenu)
document.addEventListener('wheel', hideMenu, true)
window.addEventListener('error', event => {
  post({ type: 'error', message: event.message || '导图脚本错误。' })
})

post({ type: 'ready' })
