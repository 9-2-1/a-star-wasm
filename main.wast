;;最前面粗略讲一下 wast格式
;;我参考了 MDN的教程 https://developer.mozilla.org/zh-CN/docs/WebAssembly/Understanding_the_text_format

;;大体都是 (name arg1 arg2 ...) 的格式，其中argx可以是新的括号
;;";;"打头，(; ;)之间是注释

;;name    解释
;;----    ----
;;module  整个项目 (固定的，在最外面)
;;global  全局变量 (global $标记名 类型 初始值)
;;          global默认是只读的，需要把类型调成(mut 类型)才能修改
;;memory  存储空间 (memory 最小空间页数 最大空间页数(可忽略)) 一页64KB
;;func    过程 (func $标记名 ...)
;;param   参数 (param $标记名 类型) 在func里用
;;local   本地变量 (local $标记名 类型) 在func里用
;;result  设定返回值类型 (result 类型) 在func里用
;;export  导出标记
;;          可以在 module 里面单独
;;            (export "导出名字" (内容name $标记名))
;;          也可以在内容里面
;;            (export "导出名字")
;;import  导入标记 (import "主词条" "副词条" (name arg1...))
;;          可以在 module 里面单独
;;            (import "外名字" "内名字" (内容name $标记名))
;;          也可以在内容里面
;;            (import "外名字" "内名字")
;;type   定义函数类型(参数和返回)
;;         (type $logType (param i32) (result))
;;         -> (import "debug" "log" (func (type $logType)))
;;table, data, elem没讲，因为我目前没有用它们

;;func内代码简介
;;代码可以写成后缀表达式，也可以带括号写成前缀表达式，我比较喜欢带括号
;;一般情况下带括号的操作格式是：
;;  (name arg1 arg2 ...)
;;  argx 可能是 $标记名 或者 (代码) ($标记名也可以用对应的数字代替)

;;类型列表
;;名字      说明       大小
;;----      ----       ----
;;i32       32位整数   4字节
;;i64       64位整数   4字节
;;f32       32位浮点数 8字节
;;f64       64位浮点数 8字节
;;v128      数据组合   16字节
;;externref 引用标记   不知道

;;func内常用操作(这里用 $x 代表 $标记名，(x)代表需要插入代码)

;;local.set $a (b) 把本地变量或参数a设为b
;;local.tee $a (b) 把本地变量或参数a设为b并返回b
;;local.get $a 读取本地变量或参数a
;;global.set $a (b) 把全局变量a设为b
;;global.get $a 读取全局变量a

;;类型.load offset=a (b) 从memory上的b+a位置(从0开始，单位是字节，注意！)读取类型数据
;;类型.store offset=a (b) (c) 在memory上的b+a位置保存数据c

;;(select 类型 (a) (b) (c)) 如果c不等于0返回a否则返回b,三目运算符
;;  类型在特定情况下不能忽略
;;(if (a) (then b...)) 如果那么
;;(if (a) (then b...) (else c...)) 如果那么否则
;;(loop $a b...) 设定向括号开始处跳转的标记a
;;(block $a b...) 设定向括号结尾处跳转的标记a
;;  其实loop和block也能指定返回值类型，这里不讲
;;(br $a) 跳转到标记a
;;(br_if $a (b)) 如果b跳转到标记a
;;(return) 返回(无返回值)
;;(return (a)) 返回a

;;(drop (a)) 忽略a的返回值(在wast中，有返回值的操作的返回值必须被处理，否则必须用drop忽略)

;;更多指令请查看 https://webassembly.github.io/spec/core/_download/WebAssembly.pdf
;;指路: 66页4.3.2开始是数学运算列表(使用的时候要把前面的i或者f换成完整的类型名,例如 iadd 变成 i32.add 或者 i64.add
;;      87页4.4开始是可用指令列表
;;      全是英文和各种概念，阅读前要有心理准备
;;也可以参考中文 http://webassembly.org.cn/docs/semantics/

;;看不懂的话下面全是实例，读一遍应该就大概了解了

(module
	;;调试用的函数
	(func $tell (import "debug" "tell") (param i32 i32))
	(func $inspect (import "debug" "inspect"))
	(func $log (import "debug" "log") (param i32))

	;;全局变量
	(global $mapX (export "mapX") (mut i32) (i32.const 0)) ;;地图长(1到4096)
	(global $mapY (export "mapY") (mut i32) (i32.const 0)) ;;地图长(1到4096)
	(global $mapStart (export "mapStart") (mut i32) (i32.const 0)) ;;原地图数据起点位置
	(global $diStart (export "diStart") (mut i32) (i32.const 0)) ;;方向数据起点位置
	(global $gnStart (export "gnStart") (mut i32) (i32.const 0)) ;;g(n)数据起点位置
	(global $fnStart (export "fnStart") (mut i32) (i32.const 0)) ;;f(n)数据起点位置
	(global $pqStart (export "pqStart") (mut i32) (i32.const 0)) ;;小根堆起点位置
	(global $pathStart (export "pathStart") (mut i32) (i32.const 0)) ;;路线结果开始
	(global $pathLength (export "pathLength") (mut i32) (i32.const 0)) ;;路线结果长度

	;;准备好内存
	(memory (export "memory") 1 1600) ;;64KB~100MB

	;;因为wast没有struct，没有内存管理，所以需要特别约定好数据格式
	;;ooo

	;;原地图数据 [$mapY × $mapX] 个 i32
	;;  指定格子所在位置计算方法: $mapStart + (Y × $mapX + X) × 4
	;;  以下位置计算方法类似
	;;内容格式： 目前只有0路1墙

	;;路线数据 [$mapY × $mapX] 个 i32 起点 $pathStart
	;; 代表方向标记(前往终点的方向)
	;;  0左上 1向上 2右上
	;;  3向左 4到达 5向右
	;;  6左下 7向下 8右下
	;;  X' = [B ÷ 3]↓ - 1, Y' = B % 3 - 1

	;;g(n)数据 [$mapY × $mapX] 个 i32 起点 $gnStart
	;; g(n) 当前点到终点的最短距离
	;;f(n)数据 [$mapY × $mapX] 个 i32 起点 $fnStart
	;; f(n) 当前点到终点的最短距离 + 当前点到起点的估计距离

	;;路线结果格式：
	;; 从 $pathStart 开始持续 $pathLength 个 i32
	;; 格式：X x 2¹⁶ + Y (十六进制0xXXXXYYYY)

	;;A* 算法原理简介 https://zhuanlan.zhihu.com/p/385733813

	;;测试：获取memory的页数
	;;@return {i32} 页数
	(func
		$getPage (export "getPage")
		(result i32)
		;;处于func最后的return可以省略
		(memory.size))

	;;保证memory能够装下size个字符
	;;@param {i32(unsigned)} size - memory的最小大小
	;;@return {i32} 1 成功 0 失败
	(func
		$growSize (export "growSize")
		(param $size i32)
		(result i32)

		(local $origSize i32) ;;原来的大小

		(local.set
			$size
			(i32.div_u ;;整数除法需要确定操作数是有符号还是无符号。u表示无符号，s表示有符号。
				;;加法，有符号和无符号所产生的二进制数据一样，不需要区分
				(i32.add (local.get $size) (i32.const 65535))
				(i32.const 65536))) ;;这里先把大小加上65535再除以65536，产生向上取整效果。
		;;add 加 sub 减 mul 乘 div_o 除 rem_o 余数
		;;(o为 s:有符号 u:无符号, 在浮点数类型不需要_o，因为浮点数有符号)

		(local.set $origSize (memory.size)) ;;获得原有页数

		(if
			(i32.lt_u (local.get $origSize) (local.get $size))
			;;lt_u表示无符号小于，如果大小太小就拓展大小
			;;lt_o gt_o le_o       ge_o       eq   ne
			;;小于 大于 小于或等于 大于或等于 等于 不等于
			(then
				(if
					(i32.eq
						(i32.const -1)
						(memory.grow ;;这里是拓展大小的指令，后面的减法计算拓展的页数，前面的等于用来把拓展大小指令的返回值与-1比较
							(i32.sub (local.get $size) (local.get $origSize))))
					(then
						;;等于-1就表示拓展失败了，要返回0
						(return (i32.const 0))))))
		;;如果没有摸到上面的返回0，就返回1
		;;处于func最后的return可以省略
		(i32.const 1))

	;;蓝色的格子是要搜索的格子，原定计划是把它们加入一个列表，然后每次循环扫描一遍列表。我在这里实现了一个小根堆，它可以以log n的速度快速添加元素或者取出最小的元素，非常的快。
	;;小根堆的内容格式: 正常的小根堆是n个数字，我这里把单个数字换成3个连续数字一组，比较已最后一个数字为准
	;;前两个数字分别代表x,y坐标，后面的数字是f(n)，每次这些都成组加入，成组排序，成组获取。

	;;交换两个长12个字节的区域，也就是3个i32的内容
	;;@param {i32} iPos - 第一个区域起点
	;;@param {i32} jPos - 第二个区域起点
	(func
		$swap12 (export "swap12")
		(param $iPos i32)
		(param $jPos i32)

		;;用于交换的临时变量
		(local $sw1 i64)
		(local $sw2 i32)

		;;这里用的基本交换方法：tmp = i; i = j; j = tmp;
		;;有一个技巧：前两个i32被当成了一个i64直接交换，会快一点
		(local.set $sw1 (i64.load offset=0 (local.get $iPos)))
		(local.set $sw2 (i32.load offset=8 (local.get $iPos)))

		(i64.store offset=0 (local.get $iPos) (i64.load offset=0 (local.get $jPos)))
		;;这里可以用offset代替一个add
		(i32.store offset=8 (local.get $iPos) (i32.load offset=8 (local.get $jPos)))

		(i64.store offset=0 (local.get $jPos) (local.get $sw1))
		(i32.store offset=8 (local.get $jPos) (local.get $sw2)))

	;;插入数据到小根堆并返回小根堆新的长度。
	;;使用前请保证内存分配合理，使用不当可能会覆盖其他数据。
	;;@param {i32} PQstart - 小根堆起点
	;;@param {i32} PQlength - 小根堆长度(以一组数据为单位)
	;;@param {i32} x - 格子x坐标
	;;@param {i32} y - 格子x坐标
	;;@param {i32} f - 格子f(n)值，用于排序
	;;@return {i32} 返回小根堆新的长度
	;;@example
	;;(local.set
	;;  $PQlength
	;;  (call
	;;    $PQadd
	;;    (local.get $PQstart)
	;;    (local.get $PQlength)
	;;    (local.get $x)
	;;    (local.get $y)
	;;    (local.get $fn)))
	(func
		$PQadd (export "PQadd")
		(param $PQstart i32)
		(param $PQlength i32)
		(param $x i32)
		(param $y i32)
		(param $f i32)
		(result i32)

		(local $i i32) ;;目标序号(等一会要判断交换)
		(local $iPos i32) ;;目标位置
		(local $j i32) ;;交换序号
		(local $jPos i32) ;;交换位置

		;;(call $log (i32.const 1))
		;;这里先准备把新数据追加到末尾，计算末尾的位置
		(local.set $i (local.get $PQlength))
		;; iPos = PQstart + i x 12
		(local.set
			$iPos
			(i32.add
				(local.get $PQstart)
				(i32.mul (local.get $i) (i32.const 12))))

		;;在末尾写入新数据(x,y,f)
		(i32.store offset=0 (local.get $iPos) (local.get $x))
		(i32.store offset=4 (local.get $iPos) (local.get $y))
		(i32.store offset=8 (local.get $iPos) (local.get $f))

		;;现在开始保证规则：序号x的数据一定比序号2x+1和2x+2的数据小
		(block
			$fixBreak ;;block是后跳标记，之后用(br $fixBreak)会跳到block的后面)
			(loop
				$fixConti ;;loop是前跳标记，之后用(br $fixConti)会跳到loop的前面
				;;如果i等于0，说明已经到达头部扫描成功无需继续，直接退出循环
				(if
					(i32.eqz (local.get $i))
					(then
						(br $fixBreak)))

				;;这里i是2x+1或2x+2，j是x，用i反推j
				;;j = [(i - 1) / 2]↓
				(local.set
					$j
					(i32.div_u
						(i32.sub (local.get $i) (i32.const 1))
						(i32.const 2)))
				;;计算j的位置
				(local.set
					$jPos
					(i32.add
						(local.get $PQstart)
						(i32.mul (local.get $j) (i32.const 12))))
				;;(call $log (i32.const -1))
				;;(call $log (local.get $i))
				;;(call $log (local.get $j))

				;;(call $log (i32.const -1))
				;;(call $log (local.get $i))
				;;(call $log (local.get $iPos))
				;;(call $log (local.get $j))
				;;(call $log (local.get $jPos))

				;;如果不符合规则
				(if
					(i32.lt_u
						(i32.load offset=8 (local.get $iPos))
						(i32.load offset=8 (local.get $jPos)))
					(then ;;就交换ij，使其符合规则，最多需要调整log2PQlength次
						(call $swap12 (local.get $iPos) (local.get $jPos))
						;;i变j，检查换上去的j是否符合规则
						(local.set $i (local.get $j))
						(local.set $iPos (local.get $jPos))
						;;注意这里的br在if里，意味着如果符合规则，循环就会自然退出
						(br $fixConti)))))
		;;返回长度加一
		(i32.add (local.get $PQlength) (i32.const 1)))

	;;从小根堆拿出f(n)最小的数据并返回拿出的数据所在的位置。
	;;注意拿出后将不在堆里面，记得拿出之后要自己把堆长度减去一。
	;;@param {i32} PQstart - 小根堆起点
	;;@param {i32} PQlength - 小根堆长度(以一组数据为单位)
	;;@return {i32} 返回拿出的数据所在的位置
	;;@example
	;;(local.set
	;;  $pos
	;;  (call $PQpick (local.get $PQstart) (local.get $PQlength)))
	;;(i32.load offset=0 $x (local.get $pos))
	;;(i32.load offset=4 $y (local.get $pos))
	;;(i32.load offset=8 $f (local.get $pos))
	;;(local.set $PQlength (i32.sub (local.get $PQlength) (i32.const 1)))
	(func
		$PQpick (export "PQpick")
		(param $PQstart i32)
		(param $PQlength i32)
		(result i32)

		(local $i i32)
		(local $iPos i32)
		(local $j i32)
		(local $jPos i32)

		;;eqz可以检测数字是否等于0，如果想检测不等于0，去掉(i32.eqz)即可，因为if的默认行为是在数字不等于0时成立
		;;unreachable会让程序直接报错，类似经典asm("int3")或者throw
		;;这一句是测试的时候用的
		;;(call $log (local.get $PQlength))
		(if (i32.eqz (local.get $PQlength)) (then (unreachable)))

		;;把长度减去1，计算最后一项的位置(没问题)
		(local.set $PQlength (i32.sub (local.get $PQlength) (i32.const 1)))
		(local.set
			$iPos
			(i32.add
				(local.get $PQstart)
				(i32.mul (local.get $PQlength) (i32.const 12))))
		;;把第一项和最后一项交换，这样最小的那一项会到最后面。而且因为项目数减了一，这一项在接下来的部分不会被调整。
		(call $swap12 (local.get $PQstart) (local.get $iPos))

		;;这一次要从第0项开始应用规则
		(local.set $i (i32.const 0))
		;;第0项就不需要乘法加法了
		(local.set $iPos (local.get $PQstart))

		(loop
			$conti
			;;(call $log (i32.const 667788))
			;;(call $log (local.get $i))
			;;先算出2i+1的值
			(local.set
				$j
				(i32.add
					(i32.mul (local.get $i) (i32.const 2))
					(i32.const 1)))
			;;(call $log (local.get $j))
			;;(call $log (local.get $PQlength))
			;;检查2i+1项是否存在
			(if
				(i32.lt_u (local.get $j) (local.get $PQlength))
				(then
					;;先行计算2i+1项的位置
					(local.set
						$jPos
						(i32.add
							(local.get $PQstart)
							(i32.mul (local.get $j) (i32.const 12))))
					;;检查2i+2项是否存在
					(if
						(i32.lt_u
							(i32.add (local.get $j) (i32.const 1))
							(local.get $PQlength))
						(then
							;;检查第2i+1项和第2i+2项哪个更小
							(if
								(i32.lt_u
									;;这里用offset=20=8+12来获得第2i+2项的fn值，省去加法乘法
									(i32.load offset=20 (local.get $jPos))
									(i32.load offset=8  (local.get $jPos)))
								(then
									;;如果2i+2项存在且更小，就检查2i+2项。
									(local.set $j (i32.add (local.get $j) (i32.const 1)))
									;;直接加12,不重新计算
									(local.set $jPos (i32.add (local.get $jPos) (i32.const 12)))))))

					;;如果i项较大，就和2i+1,2i+2项中存在且较小项交换并继续检查
					(if
						(i32.gt_u
							(i32.load offset=8 (local.get $iPos))
							(i32.load offset=8 (local.get $jPos)))
						(then
							(call $swap12 (local.get $iPos) (local.get $jPos))
							(local.set $i (local.get $j))
							(local.set $iPos (local.get $jPos))
							(br $conti))))))

		;;计算PQstart项，也就是之前被交换的第0项的位置，也就是要取出的数据。
		(i32.add
			(local.get $PQstart)
			(i32.mul (local.get $PQlength) (i32.const 12))))

	;;初始化内存空间
	;;@param {i32} x - 地图宽
	;;@param {i32} y - 地图高
	;;@return {i32} 1 成功 0 失败
	(func
		$init (export "init")
		(param $x i32)
		(param $y i32)
		(result i32)
		;;计算地图内存之后的位置，为了放置数据和小根堆
		;;有5个东西要安排，大小都是mapX x mapY x 4个字节。
		;;(global $mapStart (mut i32) (i32.const 0)) ;;原地图数据起点位置
		;;(global $diStart (mut i32) (i32.const 0)) ;;方向数据起点位置
		;;(global $gnStart (mut i32) (i32.const 0)) ;;g(n)数据起点位置
		;;(global $fnStart (mut i32) (i32.const 0)) ;;f(n)数据起点位置

		(global.set $mapX (local.get $x))
		(global.set $mapY (local.get $y))
		;;因为默认值是0，所以不用改
		;;(global.set $mapStart (i32.const 0))
		(global.set
			$diStart
			(i32.mul
				(i32.mul
					(local.get $x) (local.get $y)
					(i32.const 4))))
		;;因为除了pqStart之外每个部分大小一样，接下来可以直接乘
		(global.set $fnStart (i32.mul (global.get $diStart) (i32.const 2)))
		(global.set $gnStart (i32.mul (global.get $diStart) (i32.const 3)))
		(global.set $pqStart (i32.mul (global.get $diStart) (i32.const 4)))
		;;这里预计小根堆最多会包含4 x max{x,y}组数据，具体过程诶嘿
		;;但是详细路线也会被写在这里，所以要考虑这部分的大小
		;;路线长度(<格子数) x 8
		;;最后grow一下并返回grow的结果
		(call
			$growSize
			(i32.add
				(i32.mul (global.get $diStart) (i32.const 4))
				(i32.mul
					(select ;;select相当于?:三目运算符
						(i32.mul (local.get $x) (local.get $y))
						(local.get $x) (local.get $y))
					(i32.const 48)))));;12x4,12是每一组数据的的字节数

	;;填充内存(代替memory.fill)
	;;@param {i32} start 起始点
	;;@param {i32} val 要填充的i32(注意是整个i32循环填充，和原版memory.fill不一样)
	;;@param {i32} length 填充长度，必须是4的倍数
	(func
		$memset
		(param $start i32)
		(param $val i32)
		(param $length i32)

		;;如果长度不是4的倍数，就报错
		;;rem_u是无符号取余数
		(if
			(i32.rem_u (local.get $length) (i32.const 4))
			(unreachable))

		;;循环设置内容
		(block
			$setBreak
			(loop
				$setConti
				;;如果长度为0，就结束
				(br_if $setBreak (i32.eqz (local.get $length)))

				;;(call $log (local.get $start))
				(i32.store (local.get $start) (local.get $val))

				;;这里把起点+4，长度-4，到达下一项
				(local.set $start (i32.add (local.get $start) (i32.const 4)))
				(local.set $length (i32.sub (local.get $length) (i32.const 4)))
				(br $setConti))))

	;;计算起点到终点的最短路径
	;;@param {i32} startX 起始点X坐标
	;;@param {i32} startY 起始点Y坐标
	;;@param {i32} endX 终点X坐标
	;;@param {i32} endY 终点Y坐标
	;;@result {i32} 路线长度(-1失败)
	(func
		$a_star (export "a_star")
		(param $startX i32) ;;参数
		(param $startY i32)
		(param $endX   i32) ;;终点坐标，后面变成下一个格子的坐标
		(param $endY   i32)
		(result i32) ;;返回值类型

		(local $pqLength i32) ;;小根堆项目数
		(local $length i32) ;;保存格子里路线长度用的变量
		(local $pos i32) ;;格子数据位置
		(local $x i32) ;;格子坐标
		(local $y i32)
		(local $dx i32) ;;格子距离
		(local $dy i32)
		(local $x' i32) ;;前进方向
		(local $y' i32)
		(local $i i32)
		(local $c i32) ;;格子路线写入位置
		(local $di i32) ;;格子预估总路线f(n)长度
		(local $fn i32) ;;格子预估总路线f(n)长度
		(local $gn i32) ;;格子路线g(n)长度
		(local $hn i32) ;;格子预估路线h(n)长度

		;;初始化指向区域为0
		(call $memset ;;填充区域
					(global.get $diStart);;起点
					(i32.const 0);;数值
					(global.get $diStart));;长度
		;;初始化距离区域为0xffffffff(无符号最大i32数)
		(call $memset
					(global.get $fnStart)
					(i32.const 0xffffffff)
					(i32.mul (global.get $diStart) (i32.const 2)))

		;;(call $tell (global.get $mapStart) (global.get $distart))
		;;(call $tell (global.get $diStart) (global.get $distart))
		;;(call $tell (global.get $fnStart) (global.get $distart))
		;;(call $tell (global.get $gnStart) (global.get $distart))
		;;(call $tell (global.get $pqStart) (global.get $distart))

		;;一开始小根堆没有东西，长度是0
		(local.set $pqLength (i32.const 0))

		;;先计算终点f(n)，把终点加入小根堆里面
		(local.set
			$pos
			(i32.mul
				(i32.const 4)
				(i32.add
					(i32.mul (local.get $endY) (global.get $mapX))
					(local.get $endX)))) ;;终点数据位置
		(i32.store
			(i32.add (global.get $diStart) (local.get $pos))
			(i32.const 4)) ;;4表示到达终点
		;;计算估计距离h(n), 也就是没有墙的时候两点间的最短距离
		;;因为能走对角线，所以计算估计距离h(n) = max{|endX - startX|, |endY - startY|}
		(local.set $dx (i32.sub (local.get $endX) (local.get $startX)))
		(if
			(i32.lt_s (local.get $dx) (i32.const 0))
			(then
				(local.set $dx (i32.sub (i32.const 0) (local.get $dx)))))
		(local.set $dy (i32.sub (local.get $endY) (local.get $startY)))
		(if
			(i32.lt_s (local.get $dy) (i32.const 0))
			(then
				(local.set $dy (i32.sub (i32.const 0) (local.get $dy)))))
		(local.set
			$hn
			(select
				(local.get $dx) (local.get $dy)
				(i32.gt_u (local.get $dx) (local.get $dy))))
		(i32.store
			(i32.add (global.get $fnStart) (local.get $pos))
			(local.get $hn)) ;;终点f(n)是估计距离h(n)
		(i32.store
			(i32.add (global.get $gnStart) (local.get $pos))
			(i32.const 0)) ;;终点g(n)当然是0

		;;把终点加入小根堆
		(local.set
			$pqLength
			(call
				$PQadd
				(global.get $pqStart)
				(local.get $pqLength)
				(local.get $endX)
				(local.get $endY)
				(local.get $hn)))

		;;(call $tell (global.get $pqStart) (global.get $distart))

		;;现在是主要的循环，关于循环请参考上文
		(block
			$loopBreak
			(loop
				$loopConti

				;;(call $tell (global.get $mapStart) (global.get $distart))
				;;(call $tell (global.get $diStart) (global.get $distart))
				;;(call $tell (global.get $fnStart) (global.get $distart))
				;;(call $tell (global.get $gnStart) (global.get $distart))
				;;(call $tell (global.get $pqStart) (global.get $distart))
				;;(call $inspect)

				;;如果pqLength等于0，就返回失败
				(if
					(i32.eqz (local.get $pqLength))
					(then
						(return (i32.const -1))))

				;;(call $log (i32.const 99999999))
				;;(call $log (local.get $pqLength))

				;;首先获得堆里f(n)最小的点，此时pos是堆操作返回的位置
				(local.set $pos (call $PQpick (global.get $pqStart) (local.get $pqLength)))
				;;别忘了要把pqLength减去1
				(local.set $pqLength (i32.sub (local.get $pqLength) (i32.const 1)))
				;;此时endX,endY变成了当前点的坐标
				;;(call $log (i32.const 99020099))
				(local.set $endX (i32.load offset=0 (local.get $pos)))
				(local.set $endY (i32.load offset=4 (local.get $pos)))
				(local.set $fn (i32.load offset=8 (local.get $pos)))

				;;如果到达了起点，就跳到循环末尾处理路线
				(if
					(i32.eq (local.get $startX) (local.get $endX))
					(then
						(if
							(i32.eq (local.get $startY) (local.get $endY))
							(then
								(br $loopBreak)))))
				;;(call $log (i32.const 99000099))
				;;(call $log (local.get $endX))
				;;(call $log (local.get $endY))
				;;(call $log (local.get $fn))

				;;此处pos换成当前点的数据所在位置
				(local.set
					$pos
					(i32.mul
						(i32.const 4)
						(i32.add
							(i32.mul (local.get $endY) (global.get $mapX))
							(local.get $endX))))

				;;(call $log (i32.const 99190599))
				;;(call $log (local.get $pos))

				;;获取这个点标记的f(n)值，如果f(n)值和堆里记录的f(n)值不同
				;;就意味着这个点被更小的值更新过，这个记录可以忽略
				;;(call $log (i32.const 99020100))
				(br_if
					$loopConti ;;如果不一样，回到循环开始处理下一个
					(i32.ne
						(i32.load (i32.add (global.get $fnStart) (local.get $pos)))
						(local.get $fn)))

				;;(call $log (i32.const 99200299))

				;;计算下一个点g(n)值：这个点的g(n)值加上1
				;;(call $log (i32.const 99020101))
				(local.set
					$gn
					(i32.add
						(i32.const 1)
						(i32.load
							(i32.add (global.get $gnStart) (local.get $pos)))))

				;;(call $log (i32.const 99300399))

				;;用$x,$y获得所有可用方向
				(local.set $x' (i32.const -1))
				(loop
					$loopX
					(local.set $x (i32.add (local.get $endX) (local.get $x')))
					(local.set $y' (i32.const -1))
					(loop
						$loopY
						(local.set $y (i32.add (local.get $endY) (local.get $y')))

						;;检查坐标是否在地图里
						(if (i32.ge_s (local.get $x) (i32.const 0))
							(then
								(if (i32.ge_s (local.get $y) (i32.const 0))
									(then
										(if (i32.lt_s (local.get $x) (global.get $mapX))
											(then
												(if (i32.lt_s (local.get $y) (global.get $mapY))
													(then

														;;目标点的位置
														(local.set
															$pos
															(i32.mul
																(i32.const 4)
																(i32.add
																	(i32.mul (local.get $y) (global.get $mapX))
																	(local.get $x))))

														;;(call $log (i32.const 99090599))
														;;(call $log (local.get $pos))

														;;如果目标点是路
				;;(call $log (i32.const 99020102))
														(if
															(i32.eqz
																(i32.load (i32.add (global.get $mapStart) (local.get $pos))))
															(then
																;;如果目标点g(n)小于当前g(n),就更新
																;;因为对同一个点h(n)一定相同
																;;所以可以认为f(n)也小于当前f(n)，可以省去一步计算
				;;(call $log (i32.const 99020103))
																(if
																	(i32.lt_u
																		(local.get $gn)
																		(i32.load (i32.add (global.get $gnStart) (local.get $pos))))
																	(then
																		;;计算估计距离h(n)
																		(local.set $dx (i32.sub (local.get $endX) (local.get $startX)))
																		(if
																			(i32.lt_s (local.get $dx) (i32.const 0))
																			(then
																				(local.set $dx (i32.sub (i32.const 0) (local.get $dx)))))
																		(local.set $dy (i32.sub (local.get $endY) (local.get $startY)))
																		(if
																			(i32.lt_s (local.get $dy) (i32.const 0))
																			(then
																				(local.set $dy (i32.sub (i32.const 0) (local.get $dy)))))
																		(local.set
																			$hn
																			(select
																				(local.get $dx) (local.get $dy)
																				(i32.gt_u (local.get $dx) (local.get $dy))))
																		(local.set $fn (i32.add (local.get $gn) (local.get $hn)))
																		;;保存点的方向，f(n)和g(n)值
																		(i32.store
																			(i32.add (global.get $diStart) (local.get $pos))
																			(i32.sub
																				(i32.const 8)
																				(i32.add
																					(i32.mul
																						(i32.const 3)
																						(i32.add (local.get $y') (i32.const 1)))
																					(i32.add (local.get $x') (i32.const 1)))))
																		(i32.store
																			(i32.add (global.get $fnStart) (local.get $pos))
																			(local.get $fn))
																		(i32.store
																			(i32.add (global.get $gnStart) (local.get $pos))
																			(local.get $gn))

																		;;否则把点保存到小根堆，继续循环
																		(local.set
																			$pqLength
																			(call
																				$PQadd
																				(global.get $pqStart)
																				(local.get $pqLength)
																				(local.get $x)
																				(local.get $y)
																				(local.get $fn)))))))

														;;这8个括号用来应对之前的4个如果
														))))))))

						(local.set $y' (i32.add (local.get $y') (i32.const 1)))
						(br_if $loopY (i32.le_s (local.get $y') (i32.const 1))))

					(local.set $x' (i32.add (local.get $x') (i32.const 1)))
					(br_if $loopX (i32.le_s (local.get $x') (i32.const 1))))

				(br $loopConti)))

		;;(call $inspect)

		;;直接覆盖小根堆，输出返回路径
		(local.set $i (i32.const 0))
		(global.set $pathStart (local.tee $c (global.get $pqStart)))
		(loop
			$pathConti
			;;写入途径点
			;;(call $log (i32.const 99217399))
			;;(call $log (local.get $c))
			;;(call $log (local.get $startX))
			;;(call $log (local.get $startY))
			(i32.store16 offset=0 (local.get $c) (local.get $startX))
			(i32.store16 offset=2 (local.get $c) (local.get $startY))
			(local.set $i (i32.add (local.get $i) (i32.const 1)))
			(local.set $c (i32.add (local.get $c) (i32.const 4)))

			;;目标点的位置
			(local.set
				$pos
				(i32.mul
					(i32.const 4)
					(i32.add
						(i32.mul (local.get $startY) (global.get $mapX))
						(local.get $startX))))
			;;(call $log (local.get $startX))
			;;(call $log (local.get $startY))
			;;(call $log (local.get $pos))

			;;获取点方向
				;;(call $log (i32.const 99020104))
			(local.set
				$di
				(i32.load (i32.add (global.get $diStart) (local.get $pos))))
			;;(call $log (local.get $di))

			;;如果没到终点，就继续
			(if
				(i32.ne (local.get $di) (i32.const 4))
				(then
					(local.set
						$x'
						(i32.sub
							(i32.rem_u (local.get $di) (i32.const 3))
							(i32.const 1)))
					(local.set
						$y'
						(i32.sub
							(i32.div_u (local.get $di) (i32.const 3))
							(i32.const 1)))
					(local.set
						$startX
						(i32.add (local.get $startX) (local.get $x')))
					(local.set
						$startY
						(i32.add (local.get $startY) (local.get $y')))
					(br $pathConti))))
		(global.set $pathLength (local.get $i))
		(local.get $i)))
