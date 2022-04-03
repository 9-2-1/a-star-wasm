;; 最前面粗略讲一下 wast格式
;; 我参考了 MDN的教程 https://developer.mozilla.org/zh-CN/docs/WebAssembly/Understanding_the_text_format

;; 大体都是 (name arg1 arg2 ...) 的格式，其中argx可以是新的括号
;; ;;打头，(; ;)之间是注释

;; name    解释
;; ----    ----
;; module  整个项目 (固定的，在最外面)
;; global  全局变量 (global $标记名 类型 初始值)
;; memory  存储空间 (memory 最小空间页数 最大空间页数(可忽略)) 一页64KB
;; func    过程 (func $标记名 ...)
;; param   参数 (param $标记名 类型) 在func里用
;; local   本地变量 (local $标记名 类型) 在func里用
;; result  设定返回值类型 (result 类型) 在func里用
;; export  导出标记
;;           可以在 module 里面单独
;;             (export (内容name $标记名) "导出名字")
;;           也可以在内容里面
;;             (export "导出名字")
;; table, data, elem, import没讲，因为我目前没有用它们

;; func内代码简介
;; 代码可以写成后缀表达式，也可以带括号写成前缀表达式，我比较喜欢带括号
;; 一般情况下带括号的操作格式是：
;;   (name arg1 arg2 ...)
;;   argx 可能是 $标记名 或者 (代码) ($标记名也可以用对应的数字代替)

;; 类型列表
;; 名字      说明       大小
;; ----      ----       ----
;; i32       32位整数   4字节
;; i64       64位整数   4字节
;; f32       32位浮点数 8字节
;; f64       64位浮点数 8字节
;; v128      数据组合   16字节
;; externref 引用标记   不知道

;; func内常用操作(这里用 $x 代表 $标记名，(x)代表需要插入代码)

;; local.set $a (b) 把本地变量或参数a设为b
;; local.tee $a (b) 把本地变量或参数a设为b并返回b
;; local.get $a 读取本地变量或参数a
;; global.set $a (b) 把全局变量a设为b
;; global.get $a 读取全局变量a

;; 类型.load offset=a (b) 从memory上的b+a位置(从0开始，单位是字节，注意！)读取类型数据
;; 类型.store offset=a (b) (c) 在memory上的b+a位置保存数据c

;; (select 类型 (a) (b) (c)) 如果a返回b否则返回c,三目运算符
;;   类型在特定情况下不能忽略
;; (if (a) (then b...)) 如果那么
;; (if (a) (then b...) (else c...)) 如果那么否则
;; (loop $a b...) 设定向括号开始处跳转的标记a
;; (block $a b...) 设定向括号结尾处跳转的标记a
;;   其实loop和block也能指定返回值类型，这里不讲
;; (br $a) 跳转到标记a
;; (br_if $a (b)) 如果b跳转到标记a
;; (return) 返回(无返回值)
;; (return (a)) 返回a

;; (drop (a)) 忽略a的返回值(在wast中，有返回值的操作的返回值必须被处理，否则必须用drop忽略)

;; 更多指令请查看 https://webassembly.github.io/spec/core/_download/WebAssembly.pdf
;; 指路: 66页4.3.2开始是数学运算列表(使用的时候要把前面的i或者f换成完整的类型名,例如 iadd 变成 i32.add 或者 i64.add
;;       87页4.4开始是可用指令列表
;;       全是英文和各种概念，阅读前要有心理准备
;; 也可以参考中文 http://webassembly.org.cn/docs/semantics/

;; 看不懂的话下面全是实例，读一遍应该就大概了解了

(module
	;;全局变量
	(global $mapX i32 (i32.const 0) (;地图长(1到4096);))
	(global $mapY i32 (i32.const 0) (;地图长(1到4096);))
	(global $pathStart i32 (i32.const 0) (;路线结果开始;))
	(global $pathLength i32 (i32.const 0) (;路线结果长度;))

	;; 准备好内存,里面的$memory可以不要
	(memory
		$memory (export "memory")
		(;min;)1 (;max;)1600(;=100MB;))
	;; 因为wast没有struct，没有内存管理，所以需要特别约定好数据格式
	;; 内存的格式:
	;; 位置 0开始 [长 × 宽] 个 i32 是 地图内容
	;;   指定格子所在位置计算方法 (Y × 宽 + X) × 4
	;; 内容格式：
	;;  数字 = C × 2⁸ + B x 2⁴ + A × 2⁰ (十六进制0xCCCCCCBA)
	;;  A: 格子的类型 (and 0xf0 rsh 4)
	;;   0 墙 F 路 1到E 保留
	;;  B: 计算的路线方向标记 (and 0xf)
	;;   0↖ 1↑ 2↗
	;;   3← 4⊙ 5→  9到F 不用 4代表没处理
	;;   6↙ 7↓ 8↘
	;;   ( X' = [A ÷ 3]↓ - 1, Y' = A % 3 - 1 )
	;;  C: 格子目前的路线长度 (and 0xffffff00 rsh 8)
	;;   由于地图大小限制，长度不会超过 0xffffff
	;; 路线结果格式：
	;;  从 路线结果开始 开始持续 路线结果长度 个
	;;  (此处的部分可以使用Uint16Array读取，刚刚好X,Y被分开)
	;;  格式：X x 2¹⁶ + Y (十六进制0xXXXXYYYY)

	;; A* 算法原理简介
	;;   我看的 https://zhuanlan.zhihu.com/p/385733813
	;;   实现方法: 在上面的B处标记路线方向(文中的小箭头)
	;;             在上面的C处保存当前格子路线长度，也就是文中 f(n) 的值
	;;             蓝色的格子是要搜索的格子，原定计划是把它们加入一个列表，然后每次循环扫描一遍列表，但是考虑到这个项目给某个社区用了之后可能被某个群的大佬们反编译挂上去当成“傻x设计”打靶，因此我在这里实现了一个小根堆，它可以以log n的速度快速添加元素或者取出最小的元素，非常的快。

	;; 测试：获取memory的页数
	;; @return {i32} 页数
	(func
		$getPage (export "getPage")
		(result i32)
		;; 处于func最后的return可以省略
		(memory.size))

	;; 保证memory能够装下size个字符
	;; @param {i32(unsigned)} size - memory的最小大小
	;; @return {i32} 1 成功 0 失败
	(func
		$growSize (export "growSize")
		(param $size i32)
		(result i32)
		(local $origSize i32) ;; 原来的大小
		(local.set
			$size
			(i32.div_u ;; 整数除法需要确定操作数是有符号还是无符号。u表示无符号，s表示有符号。
				;; 加法，有符号和无符号所产生的二进制数据一样，不需要区分
				(i32.add (local.get $size) (i32.const 65535))
				(i32.const 65536))) ;; 这里先把大小加上65535再除以65536，产生向上取整效果。
		;; add 加 sub 减 mul 乘 div_o 除 rem_o 余数
		;; (o为 s:有符号 u:无符号, 在浮点数类型不需要_o，因为浮点数有符号)
		(local.set
			$origSize
			(memory.size)) ;; 获得原有页数
		(if
			(i32.lt_u (local.get $origSize) (local.get $size))
			;; lt_u表示无符号小于，如果大小太小就拓展大小
			;; lt_o gt_o le_o       ge_o       eq   ne
			;; 小于 大于 小于或等于 大于或等于 等于 不等于
			(then
				(if
					(i32.eq
						(i32.const -1)
						(memory.grow ;; 这里是拓展大小的指令，后面的减法计算拓展的页数，前面的等于用来把拓展大小指令的返回值与-1比较
							(i32.sub (local.get $size) (local.get $origSize))))
					(then
						;; 等于-1就表示拓展失败了，要返回0
						(return (i32.const 0))))))
		;; 如果没有摸到上面的返回0，就返回1
		;; 处于func最后的return可以省略
		(i32.const 1))
	)
