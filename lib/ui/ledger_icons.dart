import 'package:flutter/material.dart';

/// One entry in the built-in category icon library.
///
/// [name] is persisted in `ledger.json`; [data] must stay a const reference so
/// release builds can still tree-shake the Material icon font.
class LedgerIconOption {
  const LedgerIconOption(this.name, this.label, this.group, this.data);

  final String name;
  final String label;
  final String group;
  final IconData data;

  bool matches(String query) {
    final value = query.trim().toLowerCase();
    return value.isEmpty ||
        name.contains(value) ||
        label.contains(value) ||
        group.contains(value);
  }
}

/// Groups in display order.
const ledgerIconGroups = [
  '餐饮',
  '交通',
  '购物',
  '居家',
  '娱乐',
  '健康',
  '教育',
  '工作',
  '金融',
  '数码',
  '旅行',
  '其他',
  '账户',
];

/// Curated Material Icons Outlined set for money categories and accounts.
const ledgerIconOptions = <LedgerIconOption>[
  // 餐饮
  LedgerIconOption('restaurant', '餐厅', '餐饮', Icons.restaurant_outlined),
  LedgerIconOption('local_cafe', '咖啡', '餐饮', Icons.local_cafe_outlined),
  LedgerIconOption('local_bar', '酒吧', '餐饮', Icons.local_bar_outlined),
  LedgerIconOption('bakery_dining', '烘焙', '餐饮', Icons.bakery_dining_outlined),
  LedgerIconOption('lunch_dining', '午餐', '餐饮', Icons.lunch_dining_outlined),
  LedgerIconOption('dinner_dining', '晚餐', '餐饮', Icons.dinner_dining_outlined),
  LedgerIconOption(
    'breakfast_dining',
    '早餐',
    '餐饮',
    Icons.breakfast_dining_outlined,
  ),
  LedgerIconOption('ramen_dining', '面食', '餐饮', Icons.ramen_dining_outlined),
  LedgerIconOption('icecream', '甜品', '餐饮', Icons.icecream_outlined),
  LedgerIconOption('cake', '蛋糕', '餐饮', Icons.cake_outlined),
  LedgerIconOption('liquor', '酒类', '餐饮', Icons.liquor_outlined),
  LedgerIconOption('takeout_dining', '外卖', '餐饮', Icons.takeout_dining_outlined),

  // 交通
  LedgerIconOption('directions_bus', '公交', '交通', Icons.directions_bus_outlined),
  LedgerIconOption(
    'directions_subway',
    '地铁',
    '交通',
    Icons.directions_subway_outlined,
  ),
  LedgerIconOption('train', '火车', '交通', Icons.train_outlined),
  LedgerIconOption('tram', '有轨电车', '交通', Icons.tram_outlined),
  LedgerIconOption('directions_car', '汽车', '交通', Icons.directions_car_outlined),
  LedgerIconOption('local_taxi', '出租车', '交通', Icons.local_taxi_outlined),
  LedgerIconOption('two_wheeler', '电动车', '交通', Icons.two_wheeler_outlined),
  LedgerIconOption('pedal_bike', '自行车', '交通', Icons.pedal_bike_outlined),
  LedgerIconOption('flight', '飞机', '交通', Icons.flight_outlined),
  LedgerIconOption(
    'directions_boat',
    '船',
    '交通',
    Icons.directions_boat_outlined,
  ),
  LedgerIconOption(
    'local_gas_station',
    '加油',
    '交通',
    Icons.local_gas_station_outlined,
  ),
  LedgerIconOption('ev_station', '充电', '交通', Icons.ev_station_outlined),

  // 购物
  LedgerIconOption('shopping_bag', '购物袋', '购物', Icons.shopping_bag_outlined),
  LedgerIconOption('shopping_cart', '购物车', '购物', Icons.shopping_cart_outlined),
  LedgerIconOption(
    'shopping_basket',
    '购物篮',
    '购物',
    Icons.shopping_basket_outlined,
  ),
  LedgerIconOption('storefront', '商店', '购物', Icons.storefront_outlined),
  LedgerIconOption('local_mall', '商场', '购物', Icons.local_mall_outlined),
  LedgerIconOption('checkroom', '服饰', '购物', Icons.checkroom_outlined),
  LedgerIconOption('diamond', '珠宝', '购物', Icons.diamond_outlined),
  LedgerIconOption('watch', '手表', '购物', Icons.watch_outlined),
  LedgerIconOption('redeem', '礼券', '购物', Icons.redeem_outlined),
  LedgerIconOption('card_giftcard', '礼品卡', '购物', Icons.card_giftcard_outlined),
  LedgerIconOption('local_offer', '优惠', '购物', Icons.local_offer_outlined),
  LedgerIconOption('sell', '转卖', '购物', Icons.sell_outlined),

  // 居家
  LedgerIconOption('home', '住房', '居家', Icons.home_outlined),
  LedgerIconOption(
    'cleaning_services',
    '保洁',
    '居家',
    Icons.cleaning_services_outlined,
  ),
  LedgerIconOption('chair', '家具', '居家', Icons.chair_outlined),
  LedgerIconOption('bed', '寝具', '居家', Icons.bed_outlined),
  LedgerIconOption('kitchen', '厨房', '居家', Icons.kitchen_outlined),
  LedgerIconOption('microwave', '电器', '居家', Icons.microwave_outlined),
  LedgerIconOption(
    'local_laundry_service',
    '洗衣',
    '居家',
    Icons.local_laundry_service_outlined,
  ),
  LedgerIconOption('water_drop', '水费', '居家', Icons.water_drop_outlined),
  LedgerIconOption('bolt', '电费', '居家', Icons.bolt_outlined),
  LedgerIconOption('lightbulb', '灯具', '居家', Icons.lightbulb_outlined),
  LedgerIconOption('yard', '院子', '居家', Icons.yard_outlined),
  LedgerIconOption('soap', '日用品', '居家', Icons.soap_outlined),

  // 娱乐
  LedgerIconOption('sports_esports', '游戏', '娱乐', Icons.sports_esports_outlined),
  LedgerIconOption('movie', '电影', '娱乐', Icons.movie_outlined),
  LedgerIconOption('music_note', '音乐', '娱乐', Icons.music_note_outlined),
  LedgerIconOption('headphones', '耳机', '娱乐', Icons.headphones_outlined),
  LedgerIconOption(
    'sports_basketball',
    '篮球',
    '娱乐',
    Icons.sports_basketball_outlined,
  ),
  LedgerIconOption('sports_soccer', '足球', '娱乐', Icons.sports_soccer_outlined),
  LedgerIconOption('pool', '游泳', '娱乐', Icons.pool_outlined),
  LedgerIconOption('fitness_center', '健身', '娱乐', Icons.fitness_center_outlined),
  LedgerIconOption('hiking', '徒步', '娱乐', Icons.hiking_outlined),
  LedgerIconOption('forest', '露营', '娱乐', Icons.forest_outlined),
  LedgerIconOption('celebration', '聚会', '娱乐', Icons.celebration_outlined),
  LedgerIconOption('palette', '绘画', '娱乐', Icons.palette_outlined),

  // 健康
  LedgerIconOption(
    'medical_services',
    '医疗',
    '健康',
    Icons.medical_services_outlined,
  ),
  LedgerIconOption('local_hospital', '医院', '健康', Icons.local_hospital_outlined),
  LedgerIconOption('medication', '药品', '健康', Icons.medication_outlined),
  LedgerIconOption('vaccines', '疫苗', '健康', Icons.vaccines_outlined),
  LedgerIconOption('monitor_heart', '心率', '健康', Icons.monitor_heart_outlined),
  LedgerIconOption(
    'health_and_safety',
    '保险',
    '健康',
    Icons.health_and_safety_outlined,
  ),
  LedgerIconOption('spa', '理疗', '健康', Icons.spa_outlined),
  LedgerIconOption(
    'self_improvement',
    '冥想',
    '健康',
    Icons.self_improvement_outlined,
  ),
  LedgerIconOption('psychology', '心理', '健康', Icons.psychology_outlined),
  LedgerIconOption('healing', '康复', '健康', Icons.healing_outlined),
  LedgerIconOption('sick', '生病', '健康', Icons.sick_outlined),
  LedgerIconOption('bloodtype', '体检', '健康', Icons.bloodtype_outlined),

  // 教育
  LedgerIconOption('school', '学校', '教育', Icons.school_outlined),
  LedgerIconOption('menu_book', '读书', '教育', Icons.menu_book_outlined),
  LedgerIconOption('auto_stories', '阅读', '教育', Icons.auto_stories_outlined),
  LedgerIconOption('science', '科研', '教育', Icons.science_outlined),
  LedgerIconOption('code', '编程', '教育', Icons.code_outlined),
  LedgerIconOption('terminal', '命令行', '教育', Icons.terminal_outlined),
  LedgerIconOption('language', '语言', '教育', Icons.language_outlined),
  LedgerIconOption('translate', '翻译', '教育', Icons.translate_outlined),
  LedgerIconOption('calculate', '计算', '教育', Icons.calculate_outlined),
  LedgerIconOption('history_edu', '写作', '教育', Icons.history_edu_outlined),
  LedgerIconOption('draw', '手绘', '教育', Icons.draw_outlined),
  LedgerIconOption('architecture', '设计', '教育', Icons.architecture_outlined),

  // 工作
  LedgerIconOption('work', '工作', '工作', Icons.work_outlined),
  LedgerIconOption(
    'business_center',
    '公文包',
    '工作',
    Icons.business_center_outlined,
  ),
  LedgerIconOption('laptop', '笔记本', '工作', Icons.laptop_outlined),
  LedgerIconOption(
    'desktop_windows',
    '台式机',
    '工作',
    Icons.desktop_windows_outlined,
  ),
  LedgerIconOption('keyboard', '键盘', '工作', Icons.keyboard_outlined),
  LedgerIconOption('slideshow', '演示', '工作', Icons.slideshow_outlined),
  LedgerIconOption('description', '文档', '工作', Icons.description_outlined),
  LedgerIconOption('task', '任务', '工作', Icons.task_outlined),
  LedgerIconOption('event_note', '日程', '工作', Icons.event_note_outlined),
  LedgerIconOption('groups', '团队', '工作', Icons.groups_outlined),
  LedgerIconOption('badge', '工牌', '工作', Icons.badge_outlined),
  LedgerIconOption('support_agent', '客服', '工作', Icons.support_agent_outlined),

  // 金融
  LedgerIconOption('payments', '支付', '金融', Icons.payments_outlined),
  LedgerIconOption(
    'account_balance_wallet',
    '钱包',
    '金融',
    Icons.account_balance_wallet_outlined,
  ),
  LedgerIconOption(
    'account_balance',
    '银行',
    '金融',
    Icons.account_balance_outlined,
  ),
  LedgerIconOption('credit_card', '信用卡', '金融', Icons.credit_card_outlined),
  LedgerIconOption('receipt_long', '账单', '金融', Icons.receipt_long_outlined),
  LedgerIconOption('currency_yuan', '人民币', '金融', Icons.currency_yuan_outlined),
  LedgerIconOption('trending_up', '上涨', '金融', Icons.trending_up_outlined),
  LedgerIconOption('request_quote', '报价', '金融', Icons.request_quote_outlined),
  LedgerIconOption('price_check', '对账', '金融', Icons.price_check_outlined),
  LedgerIconOption(
    'monetization_on',
    '收入',
    '金融',
    Icons.monetization_on_outlined,
  ),
  LedgerIconOption('paid', '已付', '金融', Icons.paid_outlined),
  LedgerIconOption('attach_money', '金额', '金融', Icons.attach_money_outlined),

  // 数码
  LedgerIconOption('smartphone', '手机', '数码', Icons.smartphone_outlined),
  LedgerIconOption('phone_iphone', '话费', '数码', Icons.phone_iphone_outlined),
  LedgerIconOption('wifi', '宽带', '数码', Icons.wifi_outlined),
  LedgerIconOption('router', '路由器', '数码', Icons.router_outlined),
  LedgerIconOption('sim_card', '流量', '数码', Icons.sim_card_outlined),
  LedgerIconOption('cloud', '云服务', '数码', Icons.cloud_outlined),
  LedgerIconOption('computer', '电脑', '数码', Icons.computer_outlined),
  LedgerIconOption('print', '打印', '数码', Icons.print_outlined),
  LedgerIconOption(
    'videogame_asset',
    '主机游戏',
    '数码',
    Icons.videogame_asset_outlined,
  ),
  LedgerIconOption('photo_camera', '摄影', '数码', Icons.photo_camera_outlined),
  LedgerIconOption('smart_toy', '智能设备', '数码', Icons.smart_toy_outlined),
  LedgerIconOption('memory', '硬件', '数码', Icons.memory_outlined),

  // 旅行
  LedgerIconOption('flight_takeoff', '出发', '旅行', Icons.flight_takeoff_outlined),
  LedgerIconOption('hotel', '酒店', '旅行', Icons.hotel_outlined),
  LedgerIconOption('luggage', '行李', '旅行', Icons.luggage_outlined),
  LedgerIconOption('map', '地图', '旅行', Icons.map_outlined),
  LedgerIconOption('explore', '探索', '旅行', Icons.explore_outlined),
  LedgerIconOption('tour', '旅行', '旅行', Icons.tour_outlined),
  LedgerIconOption('park', '公园', '旅行', Icons.park_outlined),
  LedgerIconOption('cabin', '民宿', '旅行', Icons.cabin_outlined),
  LedgerIconOption(
    'holiday_village',
    '度假',
    '旅行',
    Icons.holiday_village_outlined,
  ),
  LedgerIconOption(
    'travel_explore',
    '周边游',
    '旅行',
    Icons.travel_explore_outlined,
  ),
  LedgerIconOption('public', '公共交通', '旅行', Icons.public_outlined),
  LedgerIconOption('beach_access', '海边', '旅行', Icons.beach_access_outlined),

  // 其他
  LedgerIconOption('pets', '宠物', '其他', Icons.pets_outlined),
  LedgerIconOption('child_care', '育儿', '其他', Icons.child_care_outlined),
  LedgerIconOption(
    'volunteer_activism',
    '公益',
    '其他',
    Icons.volunteer_activism_outlined,
  ),
  LedgerIconOption('handshake', '人情', '其他', Icons.handshake_outlined),
  LedgerIconOption('star', '收藏', '其他', Icons.star_outlined),
  LedgerIconOption('favorite', '爱好', '其他', Icons.favorite_outlined),
  LedgerIconOption('bookmark', '标记', '其他', Icons.bookmark_outlined),
  LedgerIconOption('label', '其他', '其他', Icons.label_outlined),
  LedgerIconOption('local_florist', '花草', '其他', Icons.local_florist_outlined),
  LedgerIconOption('sports_bar', '夜生活', '其他', Icons.sports_bar_outlined),
  LedgerIconOption(
    'family_restroom',
    '家庭',
    '其他',
    Icons.family_restroom_outlined,
  ),
  LedgerIconOption('diversity_3', '社交', '其他', Icons.diversity_3_outlined),

  // 账户
  LedgerIconOption('swap_horiz', '转账', '账户', Icons.swap_horiz_outlined),
  LedgerIconOption('sync_alt', '账户互转', '账户', Icons.sync_alt_outlined),
  LedgerIconOption(
    'currency_exchange',
    '换汇',
    '账户',
    Icons.currency_exchange_outlined,
  ),
  LedgerIconOption('apartment', '公积金', '账户', Icons.apartment_outlined),
  LedgerIconOption('show_chart', '基金', '账户', Icons.show_chart_outlined),
  LedgerIconOption(
    'candlestick_chart',
    '股票',
    '账户',
    Icons.candlestick_chart_outlined,
  ),
  LedgerIconOption('insights', '收益', '账户', Icons.insights_outlined),
  LedgerIconOption('trending_down', '亏损', '账户', Icons.trending_down_outlined),
  LedgerIconOption('receipt', '收据', '账户', Icons.receipt_outlined),
  LedgerIconOption('savings', '储蓄', '账户', Icons.savings_outlined),
  LedgerIconOption('price_change', '涨跌', '账户', Icons.price_change_outlined),
];

final Map<String, LedgerIconOption> ledgerIconByName = {
  for (final option in ledgerIconOptions) option.name: option,
};

/// Null means "not a known icon"; callers fall back to inheritance.
IconData? ledgerIconData(String? name) => ledgerIconByName[name]?.data;

List<LedgerIconOption> searchLedgerIcons(String query, {String? group}) => [
  for (final option in ledgerIconOptions)
    if ((group == null || option.group == group) && option.matches(query))
      option,
];
