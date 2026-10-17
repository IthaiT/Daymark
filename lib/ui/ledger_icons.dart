import 'package:flutter/material.dart';

import '../domain/ledger.dart';

/// One entry in the built-in money icon library.
///
/// [name] is what `ledger.json` stores. Glyphs live in [ledgerIconData] so each
/// one stays a direct `Icons.*` reference that release builds keep.
class LedgerIconOption {
  const LedgerIconOption(this.name, this.label, this.group);

  final String name;
  final String label;
  final String group;

  bool matches(String query) {
    final value = query.trim().toLowerCase();
    return value.isEmpty ||
        name.contains(value) ||
        label.toLowerCase().contains(value) ||
        group.contains(value);
  }
}

/// All groups in display order.
const ledgerIconGroups = [
  '餐饮',
  '交通',
  '购物',
  '居家',
  '娱乐',
  '健康',
  '教育',
  '人情',
  '通讯',
  '旅行',
  '数码',
  '收入',
  '金融',
  '账户',
  '其他',
];

/// Income categories edit a short, income-only list.
const ledgerIncomeIconGroups = ['收入', '金融', '账户', '其他'];

/// Expense categories see the spending groups; income-only icons stay out.
const ledgerExpenseIconGroups = [
  '餐饮',
  '交通',
  '购物',
  '居家',
  '娱乐',
  '健康',
  '教育',
  '人情',
  '通讯',
  '旅行',
  '数码',
  '金融',
  '账户',
  '其他',
];

/// Curated Material Icons Outlined set for money categories and accounts.
const ledgerIconOptions = <LedgerIconOption>[
  // 餐饮
  LedgerIconOption('restaurant', '餐厅', '餐饮'),
  LedgerIconOption('breakfast_dining', '早餐', '餐饮'),
  LedgerIconOption('lunch_dining', '午餐', '餐饮'),
  LedgerIconOption('dinner_dining', '晚餐', '餐饮'),
  LedgerIconOption('local_cafe', '咖啡', '餐饮'),
  LedgerIconOption('fastfood', '快餐', '餐饮'),
  LedgerIconOption('local_pizza', '披萨', '餐饮'),
  LedgerIconOption('ramen_dining', '面食', '餐饮'),
  LedgerIconOption('bakery_dining', '面包', '餐饮'),
  LedgerIconOption('icecream', '甜品', '餐饮'),
  LedgerIconOption('cake', '蛋糕', '餐饮'),
  LedgerIconOption('liquor', '酒水', '餐饮'),
  LedgerIconOption('takeout_dining', '外卖', '餐饮'),

  // 交通
  LedgerIconOption('directions_bus', '公交', '交通'),
  LedgerIconOption('directions_subway', '地铁', '交通'),
  LedgerIconOption('train', '火车', '交通'),
  LedgerIconOption('local_taxi', '打车', '交通'),
  LedgerIconOption('directions_car', '汽车', '交通'),
  LedgerIconOption('two_wheeler', '电动车', '交通'),
  LedgerIconOption('pedal_bike', '自行车', '交通'),
  LedgerIconOption('flight', '飞机', '交通'),
  LedgerIconOption('local_gas_station', '加油', '交通'),
  LedgerIconOption('local_parking', '停车', '交通'),

  // 购物
  LedgerIconOption('shopping_bag', '购物', '购物'),
  LedgerIconOption('shopping_cart', '超市', '购物'),
  LedgerIconOption('storefront', '商店', '购物'),
  LedgerIconOption('checkroom', '服饰', '购物'),
  LedgerIconOption('local_mall', '商场', '购物'),
  LedgerIconOption('watch', '手表', '购物'),
  LedgerIconOption('diamond', '珠宝', '购物'),

  // 居家
  LedgerIconOption('home', '住房', '居家'),
  LedgerIconOption('domain', '物业', '居家'),
  LedgerIconOption('bolt', '电费', '居家'),
  LedgerIconOption('water_drop', '水费', '居家'),
  LedgerIconOption('local_fire_department', '燃气', '居家'),
  LedgerIconOption('wifi', '宽带', '居家'),
  LedgerIconOption('cleaning_services', '保洁', '居家'),
  LedgerIconOption('local_laundry_service', '洗衣', '居家'),
  LedgerIconOption('chair', '家具', '居家'),
  LedgerIconOption('handyman', '维修', '居家'),

  // 娱乐
  LedgerIconOption('movie', '电影', '娱乐'),
  LedgerIconOption('sports_esports', '游戏', '娱乐'),
  LedgerIconOption('music_note', '音乐', '娱乐'),
  LedgerIconOption('sports_basketball', '运动', '娱乐'),
  LedgerIconOption('fitness_center', '健身', '娱乐'),
  LedgerIconOption('pool', '游泳', '娱乐'),
  LedgerIconOption('theater_comedy', '演出', '娱乐'),
  LedgerIconOption('celebration', '聚会', '娱乐'),

  // 健康
  LedgerIconOption('local_hospital', '医院', '健康'),
  LedgerIconOption('medical_services', '医疗', '健康'),
  LedgerIconOption('medication', '药品', '健康'),
  LedgerIconOption('vaccines', '疫苗', '健康'),
  LedgerIconOption('monitor_heart', '体检', '健康'),
  LedgerIconOption('health_and_safety', '保险', '健康'),
  LedgerIconOption('healing', '康复', '健康'),

  // 教育
  LedgerIconOption('school', '学费', '教育'),
  LedgerIconOption('menu_book', '书籍', '教育'),
  LedgerIconOption('edit_note', '文具', '教育'),
  LedgerIconOption('translate', '语言课', '教育'),
  LedgerIconOption('draw', '兴趣班', '教育'),

  // 人情
  LedgerIconOption('card_giftcard', '礼物', '人情'),
  LedgerIconOption('volunteer_activism', '公益', '人情'),
  LedgerIconOption('handshake', '人情来往', '人情'),
  LedgerIconOption('local_florist', '鲜花', '人情'),

  // 通讯
  LedgerIconOption('phone_iphone', '话费', '通讯'),
  LedgerIconOption('sim_card', '流量', '通讯'),
  LedgerIconOption('router', '路由器', '通讯'),

  // 旅行
  LedgerIconOption('flight_takeoff', '出行', '旅行'),
  LedgerIconOption('hotel', '住宿', '旅行'),
  LedgerIconOption('luggage', '行李', '旅行'),
  LedgerIconOption('map', '地图', '旅行'),
  LedgerIconOption('beach_access', '度假', '旅行'),

  // 数码
  LedgerIconOption('devices', '数码', '数码'),
  LedgerIconOption('smartphone', '手机', '数码'),
  LedgerIconOption('computer', '电脑', '数码'),
  LedgerIconOption('headphones', '耳机', '数码'),
  LedgerIconOption('smart_toy', 'AI', '数码'),

  // 收入
  LedgerIconOption('work', '工资', '收入'),
  LedgerIconOption('emoji_events', '奖金', '收入'),
  LedgerIconOption('apartment', '公积金', '收入'),
  LedgerIconOption('percent', '利息', '收入'),
  LedgerIconOption('donut_large', '分红', '收入'),
  LedgerIconOption('receipt_long', '报销', '收入'),
  LedgerIconOption('redeem', '红包', '收入'),
  LedgerIconOption('work_history', '兼职', '收入'),
  LedgerIconOption('home_work', '房租', '收入'),
  LedgerIconOption('undo', '退款', '收入'),
  LedgerIconOption('trending_up', '投资收益', '收入'),
  LedgerIconOption('attach_money', '其他收入', '收入'),

  // 金融
  LedgerIconOption('payments', '支付', '金融'),
  LedgerIconOption('account_balance_wallet', '钱包', '金融'),
  LedgerIconOption('account_balance', '银行', '金融'),
  LedgerIconOption('credit_card', '信用卡', '金融'),
  LedgerIconOption('currency_yuan', '人民币', '金融'),
  LedgerIconOption('savings', '储蓄', '金融'),
  LedgerIconOption('receipt', '账单', '金融'),
  LedgerIconOption('request_quote', '请款', '金融'),
  LedgerIconOption('price_check', '对账', '金融'),

  // 账户
  LedgerIconOption('swap_horiz', '转账', '账户'),
  LedgerIconOption('sync_alt', '账户互转', '账户'),
  LedgerIconOption('currency_exchange', '换汇', '账户'),
  LedgerIconOption('show_chart', '基金', '账户'),
  LedgerIconOption('candlestick_chart', '股票', '账户'),
  LedgerIconOption('insights', '收益', '账户'),

  // 其他
  LedgerIconOption('label', '其他', '其他'),
  LedgerIconOption('star', '收藏', '其他'),
  LedgerIconOption('bookmark', '标记', '其他'),
  LedgerIconOption('more_horiz', '更多', '其他'),
];

/// Every glyph is a direct const reference so the release font keeps it.
///
/// Add new icons here (and to [ledgerIconOptions]) instead of storing an
/// [IconData] inside the option object.
IconData? ledgerIconData(String? name) => switch (name) {
  'restaurant' => Icons.restaurant_outlined,
  'breakfast_dining' => Icons.breakfast_dining_outlined,
  'lunch_dining' => Icons.lunch_dining_outlined,
  'dinner_dining' => Icons.dinner_dining_outlined,
  'local_cafe' => Icons.local_cafe_outlined,
  'fastfood' => Icons.fastfood_outlined,
  'local_pizza' => Icons.local_pizza_outlined,
  'ramen_dining' => Icons.ramen_dining_outlined,
  'bakery_dining' => Icons.bakery_dining_outlined,
  'icecream' => Icons.icecream_outlined,
  'cake' => Icons.cake_outlined,
  'liquor' => Icons.liquor_outlined,
  'takeout_dining' => Icons.takeout_dining_outlined,
  'directions_bus' => Icons.directions_bus_outlined,
  'directions_subway' => Icons.directions_subway_outlined,
  'train' => Icons.train_outlined,
  'local_taxi' => Icons.local_taxi_outlined,
  'directions_car' => Icons.directions_car_outlined,
  'two_wheeler' => Icons.two_wheeler_outlined,
  'pedal_bike' => Icons.pedal_bike_outlined,
  'flight' => Icons.flight_outlined,
  'local_gas_station' => Icons.local_gas_station_outlined,
  'local_parking' => Icons.local_parking_outlined,
  'shopping_bag' => Icons.shopping_bag_outlined,
  'shopping_cart' => Icons.shopping_cart_outlined,
  'storefront' => Icons.storefront_outlined,
  'checkroom' => Icons.checkroom_outlined,
  'local_mall' => Icons.local_mall_outlined,
  'watch' => Icons.watch_outlined,
  'diamond' => Icons.diamond_outlined,
  'home' => Icons.home_outlined,
  'domain' => Icons.domain_outlined,
  'bolt' => Icons.bolt_outlined,
  'water_drop' => Icons.water_drop_outlined,
  'local_fire_department' => Icons.local_fire_department_outlined,
  'wifi' => Icons.wifi_outlined,
  'cleaning_services' => Icons.cleaning_services_outlined,
  'local_laundry_service' => Icons.local_laundry_service_outlined,
  'chair' => Icons.chair_outlined,
  'handyman' => Icons.handyman_outlined,
  'movie' => Icons.movie_outlined,
  'sports_esports' => Icons.sports_esports_outlined,
  'music_note' => Icons.music_note_outlined,
  'sports_basketball' => Icons.sports_basketball_outlined,
  'fitness_center' => Icons.fitness_center_outlined,
  'pool' => Icons.pool_outlined,
  'theater_comedy' => Icons.theater_comedy_outlined,
  'celebration' => Icons.celebration_outlined,
  'local_hospital' => Icons.local_hospital_outlined,
  'medical_services' => Icons.medical_services_outlined,
  'medication' => Icons.medication_outlined,
  'vaccines' => Icons.vaccines_outlined,
  'monitor_heart' => Icons.monitor_heart_outlined,
  'health_and_safety' => Icons.health_and_safety_outlined,
  'healing' => Icons.healing_outlined,
  'school' => Icons.school_outlined,
  'menu_book' => Icons.menu_book_outlined,
  'edit_note' => Icons.edit_note_outlined,
  'translate' => Icons.translate_outlined,
  'draw' => Icons.draw_outlined,
  'card_giftcard' => Icons.card_giftcard_outlined,
  'volunteer_activism' => Icons.volunteer_activism_outlined,
  'handshake' => Icons.handshake_outlined,
  'local_florist' => Icons.local_florist_outlined,
  'phone_iphone' => Icons.phone_iphone_outlined,
  'sim_card' => Icons.sim_card_outlined,
  'router' => Icons.router_outlined,
  'flight_takeoff' => Icons.flight_takeoff_outlined,
  'hotel' => Icons.hotel_outlined,
  'luggage' => Icons.luggage_outlined,
  'map' => Icons.map_outlined,
  'beach_access' => Icons.beach_access_outlined,
  'devices' => Icons.devices_outlined,
  'smartphone' => Icons.smartphone_outlined,
  'computer' => Icons.computer_outlined,
  'headphones' => Icons.headphones_outlined,
  'smart_toy' => Icons.smart_toy_outlined,
  'work' => Icons.work_outlined,
  'emoji_events' => Icons.emoji_events_outlined,
  'apartment' => Icons.apartment_outlined,
  'percent' => Icons.percent_outlined,
  'donut_large' => Icons.donut_large_outlined,
  'receipt_long' => Icons.receipt_long_outlined,
  'redeem' => Icons.redeem_outlined,
  'work_history' => Icons.work_history_outlined,
  'home_work' => Icons.home_work_outlined,
  'undo' => Icons.undo_outlined,
  'trending_up' => Icons.trending_up_outlined,
  'attach_money' => Icons.attach_money_outlined,
  'payments' => Icons.payments_outlined,
  'account_balance_wallet' => Icons.account_balance_wallet_outlined,
  'account_balance' => Icons.account_balance_outlined,
  'credit_card' => Icons.credit_card_outlined,
  'currency_yuan' => Icons.currency_yuan_outlined,
  'savings' => Icons.savings_outlined,
  'receipt' => Icons.receipt_outlined,
  'request_quote' => Icons.request_quote_outlined,
  'price_check' => Icons.price_check_outlined,
  'swap_horiz' => Icons.swap_horiz_outlined,
  'sync_alt' => Icons.sync_alt_outlined,
  'currency_exchange' => Icons.currency_exchange_outlined,
  'show_chart' => Icons.show_chart_outlined,
  'candlestick_chart' => Icons.candlestick_chart_outlined,
  'insights' => Icons.insights_outlined,
  'label' => Icons.label_outlined,
  'star' => Icons.star_outlined,
  'bookmark' => Icons.bookmark_outlined,
  'more_horiz' => Icons.more_horiz_outlined,
  _ => null,
};

final Map<String, LedgerIconOption> ledgerIconByName = {
  for (final option in ledgerIconOptions) option.name: option,
};

List<String> ledgerIconGroupsFor(MoneyKind kind) =>
    kind == MoneyKind.income ? ledgerIncomeIconGroups : ledgerExpenseIconGroups;

List<LedgerIconOption> searchLedgerIcons(String query, {Set<String>? groups}) =>
    [
      for (final option in ledgerIconOptions)
        if ((groups == null || groups.contains(option.group)) &&
            option.matches(query))
          option,
    ];
