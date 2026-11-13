-- 餐厅流转配置：维护客流、搬运速度、包装显示上限和购买节奏
--!strict
return {
	WorkerSpeed = 8, -- 服务员移动速度，studs/s
	CustomerSpeed = 8, -- 顾客移动速度，studs/s
	ArrivalSeconds = 3, -- 每次尝试生成一位顾客的在线间隔，秒
	CustomerLimit = 6, -- 进店与等待顾客总上限，不包含已购买离店的顾客
	PurchaseSeconds = 1, -- 全店两次成交的最小间隔，秒；缺货不累计购买额度
	VisualPackageLimit = 12, -- 每处库存或搬运者最多展示的代表包装盒数
	QueueSpacing = 1.5, -- 排队顾客之间距离，studs
	ArrivalDistance = 0.05, -- 移动到达判定距离，studs
}
