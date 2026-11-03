# 功能源码

- axi：DDR 读写、帧管理及历史回放。
- cmos_i2c：SC2210 配置、I2C 和自动曝光控制。
- control：按键、菜单、阈值、跨时钟控制。
- isp：RAW 转 RGB、灰度、中值/高斯、Sobel/Canny、形态学、叠加及视频流水线。
- inspection：边缘目标提取、几何特征、模板比较、跟踪和判定；兼容/回归模块原样保留。
- paired：图像与检测结果同帧配对、传输及录入缓存。
- ui：UI、帧率、快照及字库。
- hdmi_ip：HDMI 编码。
- lcd_driver.v、lcd_para.v：显示时序。

正式顶层为 ../Ti60_top.v，综合文件列表以 ../Ti60_Edge_Detection.xml 为准。
UI 的 .mem、.vh 和字符串源文件不可当作缓存删除。
