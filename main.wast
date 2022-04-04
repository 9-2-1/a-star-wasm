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
;;            (export (内容name $标记名) "导出名字")
;;          也可以在内容里面
;;            (export "导出名字")
;;import  导入标记 (import "主词条" "副词条" (name arg1...))
;;          例如 (import "debug" "log" (func (type $logType)))
;;               (import "info" "memory" (memory))
;;               (import "config" "size" (global $configSize i32))
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

;;(select 类型 (a) (b) (c)) 如果a返回b否则返回c,三目运算符
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
	(type $tellType (func (param i32)))
	(import "debug" "tell" (func $tell (type $tellType)))
	(type $logType (func (param i32)))
	(import "debug" "log" (func $log (type $logType)))

	;;全局变量
	(global $mapX (export "mapX") (mut i32) (i32.const 0)) ;;地图长(1到4096)
	(global $mapY (export "mapY") (mut i32) (i32.const 0)) ;;地图长(1到4096)
	(global $mapStart (mut i32) (i32.const 0)) ;;原地图数据起点位置
	(global $diStart (mut i32) (i32.const 0)) ;;方向数据起点位置
	(global $gnStart (mut i32) (i32.const 0)) ;;g(n)数据起点位置
	(global $fnStart (mut i32) (i32.const 0)) ;;f(n)数据起点位置
	(global $pathStart (mut i32) (i32.const 0)) ;;路线结果开始
	(global $pathLength (mut i32) (i32.const 0)) ;;路线结果长度

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

		(local.set
			$origSize
			(memory.size)) ;;获得原有页数

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

	;;蓝色的格子是要搜索的格子，原定计划是把它们加入一个列表，然后每次循环扫描一遍列表，但是考虑到这个项目给某个社区用了之后可能被某个群的大佬们反编译挂上去当成“傻x设计”打靶，因此我在这里实现了一个小根堆，它可以以log n的速度快速添加元素或者取出最小的元素，非常的快。
	;;小根堆的内容格式: 正常的小根堆是n个数字，我这里把单个数字换成3个连续数字一组，比较已最后一个数字为准
	;;前两个数字分别代表x,y坐标，后面的数字是f(n)，每次这些都成组加入，成组排序，成组获取。

	;;交换两个长12个字节的区域，也就是3个i32的内容
	;;@param {i32} i12 - 第一个区域起点
	;;@param {i32} j12 - 第二个区域起点
	(func
		$swap12 (export "swap12")
		(param $i12 i32)
		(param $j12 i32)

		;;用于交换的临时变量
		(local $sw1 i64)
		(local $sw2 i32)

		;;这里用的基本交换方法：tmp = i; i = j; j = tmp;
		(local.set $sw1 (i64.load offset=0 (local.get $i12)))
		(local.set $sw2 (i32.load offset=8 (local.get $i12)))

		;;有一个技巧：前两个i32被当成了一个i64直接交换，会快一点
		(i64.store offset=0 (local.get $i12) (i64.load offset=0 (local.get $j12)))
		;;这里可以用offset代替一个add
		(i32.store offset=8 (local.get $i12) (i32.load offset=8 (local.get $j12)))

		(i64.store offset=0 (local.get $j12) (local.get $sw1))
		(i32.store offset=8 (local.get $j12) (local.get $sw2)))

	;;插入数据到小根堆
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
		(local $i12 i32) ;;目标位置
		(local $j i32) ;;交换序号
		(local $j12 i32) ;;交换位置

		;;(call $log (i32.const 1))
		(local.set $i (local.get $PQlength))
		;;cheng 12
		(local.set
			$i12
			(i32.add
				(local.get $PQstart)
				(i32.mul (local.get $i) (i32.const 12))))

		;;baocundaozuihoumian
		(i32.store offset=0 (local.get $i12) (local.get $x))
		(i32.store offset=4 (local.get $i12) (local.get $y))
		(i32.store offset=8 (local.get $i12) (local.get $f))

		;;kaishichuli rules
		(loop
			$loop ;;woyaoyong return
			(if
				(i32.eqz (local.get $i))
				(then
					(return (i32.add (local.get $PQlength) (i32.const 1)))))

			(local.set
				$j
				(i32.div_u
					(i32.sub (local.get $i) (i32.const 1))
					(i32.const 2)))
			(local.set
				$j12
				(i32.add
					(local.get $PQstart)
					(i32.mul (local.get $j) (i32.const 12))))
			;;(call $log (i32.const -1))
			;;(call $log (local.get $i))
			;;(call $log (local.get $j))

			;;(call $log (i32.const -1))
			;;(call $log (local.get $i))
			;;(call $log (local.get $i12))
			;;(call $log (local.get $j))
			;;(call $log (local.get $j12))
			(if
				(i32.lt_u
					(i32.load offset=8 (local.get $i12))
					(i32.load offset=8 (local.get $j12)))
				(then
					(call $swap12 (local.get $i12) (local.get $j12))))

			(local.set $i (local.get $j))
			(local.set $i12 (local.get $j12))
			(br $loop))
		(unreachable))

	(func
		$PQpick (export "PQpick")
		(param $PQstart i32)
		(param $PQlength i32)
		(result i32)

		(local $i i32) ;;head
		(local $i12 i32) ;;offset
		(local $j i32) ;;head
		(local $j12 i32) ;;offset

		(local.set $PQlength (i32.sub (local.get $PQlength) (i32.const 1)))
		(local.set
			$i12
			(i32.add
				(local.get $PQstart)
				(i32.mul (local.get $PQlength) (i32.const 12))))
		(call $swap12 (local.get $PQstart) (local.get $i12))

		(local.set $i (i32.const 0))
		;;(local.set
		;;	$i12
		;;	(i32.add
		;;		(local.get $PQstart)
		;;		(i32.mul (local.get $i) (i32.const 12))))
		(local.set $i12 (local.get $PQstart)) ;;$i = 0

		(loop
			$conti
			;;(call $log (i32.const 667788))
			;;(call $log (local.get $i))
			(local.set
				$j
				(i32.add
					(i32.mul (local.get $i) (i32.const 2))
					(i32.const 1)))
			;;(call $log (local.get $j))
			;;(call $log (local.get $PQlength))
			(if
				(i32.lt_u (local.get $j) (local.get $PQlength))
				(then
					(local.set
						$j12
						(i32.add
							(local.get $PQstart)
							(i32.mul (local.get $j) (i32.const 12))))
					(if
						(i32.lt_u
							(i32.add (local.get $j) (i32.const 1))
							(local.get $PQlength))
						(then
							(if
								(i32.gt_u
									(i32.load offset=8  (local.get $j12))
									(i32.load offset=20 (local.get $j12))) ;;8+12
								(then
									(local.set $j (i32.add (local.get $j) (i32.const 1)))
									(local.set $j12 (i32.add (local.get $j12) (i32.const 12)))))))

					(if
						(i32.gt_u
							(i32.load offset=8 (local.get $i12))
							(i32.load offset=8 (local.get $j12)))
						(then
							(call $swap12 (local.get $i12) (local.get $j12))))
					(local.set $i (local.get $j))
					(local.set $i12 (local.get $j12))
					(br $conti))))

		(i32.add
			(local.get $PQstart)
			(i32.mul (local.get $PQlength) (i32.const 12))))

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
		(param $endX   i32)
		(param $endY   i32)
		(result i32) ;;返回值类型

		(local $PQstart i32) ;;这里是一个x根堆
		(local $PQlength i32)
		(local $length i32) ;;保存格子里路线长度用的变量
		(local $pos i32) ;;格子数据位置
		(local $x i32)
		(local $y i32)
		(local $x' i32)
		(local $y' i32)
		(local $i i32)
		(local $cell i32) ;;格子数据
		(local $cellA i32) ;;A: 格子类型 (0墙 F路)
		(local $cellB i32) ;;B: 路线类型，参考上文
		(local $cellC i32) ;;C: 路线f(n)=g(n)+h(n)长度
		(local $fn i32)
		;;计算地图内存之后的位置，为了放置x根堆

		(local.set
			$PQstart
			(i32.mul
				(i32.mul (global.get $mapX) (global.get $mapY))
				(i32.const 4)))

		(call $log (local.get $PQstart))
		(if
			(local.get $PQstart)
			(then
				(local.set $i (i32.const 0))
				(loop
					$clearLoop
					(i32.store
						(local.get $i)
						(i32.or
							(i32.const 0xffffff40)
							(i32.and (i32.const 0xf) (i32.load (local.get $i)))))

					(local.set
						$i
						(i32.add (local.get $i) (i32.const 4)))
					(br_if $clearLoop (i32.lt_u (local.get $i) (local.get $PQstart))))))

		(call $tell)
		(local.set $PQlength (i32.const 0))

		;;priorityQueue neibudigeshi
		;;12bit 1danwei
		;;i32 i32 i32 - X Y Len+Dis

		;;xianchushihua, baqidianzhijiejiajingqu
		(call
			$PQadd
			(local.get $PQstart)
			(local.get $PQlength)
			(local.get $endX) ;;xian tui end
			(local.get $endY)
			(i32.const 0));;len=0
		(local.set
			$PQlength
			(i32.add (local.get $PQlength) (i32.const 1)))

		(block
			$loopBreak
			(loop
				$loopContinue
				;;xunhuandebiaozunxiefa.
				;;block yonglai daduanxunhuan
				;;loop yonglai jiexuxunhuan

				;;shouxian, quchuyouxuanjieguo
				(local.set $pos (call $PQpick (local.get $PQstart) (local.get $PQlength)))
				(local.set $endX (i32.load offset=0 (local.get $pos)))
				(local.set $endY (i32.load offset=4 (local.get $pos)))
				(local.set $length (i32.load offset=8 (local.get $pos)))

				(local.set $x' (i32.const -1))
				(loop
					$loopX
					(local.set $x (i32.add (local.get $endX) (local.get $x')))
					(local.set $y' (i32.const -1))
					(loop
						$loopY
						(local.set $y (i32.add (local.get $endY) (local.get $y')))

						(local.set
							$pos
							(i32.mul (i32.add (i32.mul (local.get $y) (global.get $mapX)) (local.get $x)) (i32.const 4)))
						(local.set $cell (i32.load (local.get $pos)))
						;;(i32.load (local.get $cell) (local.get $pos))
						(local.set $cellC (i32.shr_u (local.get $cell) (i32.const 8)))
						(local.set
							$cellB
							(i32.or
								(i32.const 0xf)
								(i32.shr_u (local.get $cell) (i32.const 4))))
						(local.set $cellA (i32.or (i32.const 0xf) (local.get $cell)))

						(if
							(i32.lt_u (local.get $fn) (local.get $cellC))
							(then
								(local.set
									$cellB
									(i32.or
										(i32.const 0xf)
										(i32.shr_u (local.get $cell) (i32.const 4))))
								(local.set $cellA (i32.or (i32.const 0xf) (local.get $cell)))
								(local.set
									$cellB
									(i32.sub
										(i32.const 12)
										(i32.add
											(local.get $x')
											(i32.mul (local.get $y') (i32.const 3)))))
								(local.set $cellC (local.get $fn))
								(i32.store
									(local.get $pos)
									(i32.or
										(i32.or
											(local.get $cellA)
											(i32.shl (local.get $cellB) (i32.const 4)))
										(i32.shl (local.get $cellC) (i32.const 8))))
								(local.set
									$PQlength
									(call
										$PQadd
										(local.get $PQstart)
										(local.get $PQlength)
										(local.get $endX) ;;xian tui end
										(local.get $endY)
										(i32.const 0))))) ;;len=0

						(local.set $y' (i32.add (local.get $y') (i32.const 1)))
						(br_if $loopY (i32.le_s (local.get $y') (i32.const 1))))

					(local.set $x' (i32.add (local.get $x') (i32.const 1)))
					(br_if $loopX (i32.le_s (local.get $x') (i32.const 1))))

				(local.set
					$PQlength
					(call
						$PQadd
						(local.get $PQstart)
						(local.get $PQlength)
						(local.get $endX)
						(local.get $endY)
						(i32.const 0))) ;;len=0

				(br_if
					$loopContinue
					(local.get $PQlength))
				;;budengyu0
				))

		;;(return (local.get $mapX))
		(i32.const 0))
	)
