#!/sbin/sh
#Thank lyq1996
dtc=$PWD/tools/dtc
dtp=$PWD/tools/dtp
bbox=$PWD/tools/busybox
magiskboot=$PWD/tools/magiskboot

file_getprop() { $bbox grep "^$2=" "$1" | $bbox cut -d= -f2-; }
screen=$(file_getprop anykernel.sh do.refresh_rate)
cpu_offset=$(file_getprop anykernel.sh do.cpu_offset)
dts_backup=$(file_getprop anykernel.sh do.dts_backup)
screen=${screen:="0"}
cpu_offset=${cpu_offset:="0"}
dts_backup=${dts_backup:="0"}

ui_print() {
  until [ ! "$1" ]; do
    echo -e "ui_print $1
      ui_print" >> /proc/self/fd/$OUTFD;
    shift;
  done;
}

if [ "$screen" = "0" ] && [ "$cpu_offset" = "0" ]; then
	exit 0
fi

$bbox dd if=/dev/block/bootdevice/by-name/boot of=$PWD/tools/boot.img
$magiskboot unpack $PWD/tools/boot.img

$dtp -i kernel_dtb
if [ "$?" != "0" ]; then
	ui_print " " "Split dtb file error"
	exit 1
fi

# decompile dtb
dtb_count=$(ls -lh kernel_dtb-* | wc -l)
board_id=$($bbox cat /proc/device-tree/qcom,board-id | $bbox xxd -p | $bbox xargs echo | $bbox sed 's/ //g' | $bbox sed 's/.\{8\}/&\n/g' | $bbox sed 's/^0\{6\}/0x/g' | $bbox sed 's/^0\{5\}/0x/g' | $bbox sed 's/^0\{4\}/0x/g' | $bbox sed 's/^0\{3\}/0x/g' | $bbox sed 's/^0\{2\}/0x/g' | $bbox sed 's/^0\{1\}x*/0x/g' | $bbox tr '\n' ' ' | $bbox sed 's/ *$/\n/g')
msm_id=$($bbox cat /proc/device-tree/qcom,msm-id | $bbox xxd -p | $bbox xargs echo | $bbox sed 's/ //g' | $bbox sed 's/.\{8\}/&\n/g' | $bbox sed 's/^0\{6\}/0x/g' | $bbox sed 's/^0\{5\}/0x/g' | $bbox sed 's/^0\{4\}/0x/g' | $bbox sed 's/^0\{3\}/0x/g' | $bbox sed 's/^0\{2\}/0x/g' | $bbox sed 's/^0\{1\}x*/0x/g' | $bbox tr '\n' ' ' | $bbox sed 's/ *$/\n/g')

i=0
while [ $i -lt $dtb_count ]; do
	$dtc -q -I dtb -O dts kernel_dtb-$i -o $PWD/tools/kernel_dtb_$i.dts
	dts_board_id=$($bbox cat $PWD/tools/kernel_dtb_$i.dts | $bbox grep qcom,board-id | $bbox sed -e 's/[\t]*qcom,board-id = <//g' | $bbox sed 's/>;//g')
	dts_msm_id=$($bbox cat $PWD/tools/kernel_dtb_$i.dts | $bbox grep qcom,msm-id | $bbox sed -e 's/[\t]*qcom,msm-id = <//g' | $bbox sed 's/>;//g')
	echo "kernel_dtb_$i.dts board_id: $dts_board_id, msm_id: $dts_msm_id"
	if [ "$dts_board_id" = "$board_id" ] && [ "$dts_msm_id" = "$msm_id" ]; then
		echo "Got it, let's patch kernel_dtb_$i.dts"
		break
	fi
	$bbox rm -f $PWD/tools/kernel_dtb_$i.dts
	i=$((i + 1))
done
case $i in
$dtb_count)
	ui_print " " "Unable to found matching kernel_dtb.dts!"
	exit 1
;;
esac

# change screen refresh rate
if [ "$screen" != "0" ]; then
	srr=qcom,mdss-dsi-panel-framerate
	max_srr=qcom,mdss-dsi-max-refresh-rate
	new_ssr_=$(printf "0x%x" $screen)
	$bbox sed -i "s/$srr = <[^)]*>/$srr = <$new_ssr_>/g" $PWD/tools/kernel_dtb_$i.dts
	$bbox sed -i "s/$max_srr = <[^)]*>/$max_srr = <$new_ssr_>/g" $PWD/tools/kernel_dtb_$i.dts
fi

# apply voltage offset!
$bbox cat $PWD/tools/kernel_dtb_$i.dts | $bbox grep qcom,cpr-open-loop-voltage-fuse-adjustment > $PWD/tools/filebuff_o
$bbox cat $PWD/tools/kernel_dtb_$i.dts | $bbox grep qcom,cpr-closed-loop-voltage-fuse-adjustment >> $PWD/tools/filebuff_o

cp $PWD/tools/filebuff_o $PWD/tools/filebuff_s
o_line=$($bbox cat $PWD/tools/filebuff_o | $bbox sed -e 's/[\t]*.*<//g' | $bbox sed 's/>;//g' | wc -l)

j=1
while [ $j -le $o_line ]; do
	line=$($bbox cat $PWD/tools/filebuff_o | $bbox awk "NR==$j")
	open_loop_voltage=$(echo "$line" | $bbox sed -e 's/[\t]*.*<//g' | $bbox sed 's/>;//g' | $bbox sed 's/\(0x[^ ]* \)\{4\}/&\n/g')

	for l in 1 2 4; do
		rows=$(echo "$open_loop_voltage" | $bbox awk "NR==$l")
		loop_adjust=$(echo "$rows" | $bbox sed 's/ $//g')
		new_v1=$(($(echo "$loop_adjust" | awk '{print $1}') + (9 * $cpu_offset / 10) * 1000))
		new_v2=$(($(echo "$loop_adjust" | awk '{print $2}') + (9 * $cpu_offset / 10) * 1000))
		new_v3=$(($(echo "$loop_adjust" | awk '{print $3}') + $cpu_offset * 1000))
		new_v4=$(($(echo "$loop_adjust" | awk '{print $4}') + $cpu_offset * 1000))
		new_v=$(printf "0x%x 0x%x 0x%x 0x%x\n" $new_v1 $new_v2 $new_v3 $new_v4 | $bbox sed 's/0xf\{8\}/0x/g')
		$bbox sed -i "s/$loop_adjust/$new_v/g" $PWD/tools/filebuff_s
	done

	ori_line=$($bbox cat $PWD/tools/filebuff_o | $bbox awk "NR==$j")
	mod_line=$($bbox cat $PWD/tools/filebuff_s | $bbox awk "NR==$j")
	$bbox sed -i "s/$ori_line/$mod_line/g" $PWD/tools/kernel_dtb_$i.dts

	case $? in
	1)
		ui_print " " "Unable to patched kernel_dtb_$i.dts!"
		exit 1
	;;
	esac
	j=$((j + 1))
done

# backup dts
if [ "$dts_backup" = "1" ]; then
	$bbox cp $PWD/tools/kernel_dtb_$i.dts /sdcard/Android/backup.dts
	ui_print " " "Backup kernel_dtb_$i.dts to /sdcard/Android/backup.dts"
fi

# compile dts to dtb
$dtc -q -I dts -O dtb $PWD/tools/kernel_dtb_$i.dts -o kernel_dtb-$i

# generate new dtb
i=0
> kernel_dtb
while [ $i -lt $dtb_count ]; do
	$bbox cat kernel_dtb-$i >> kernel_dtb
	i=$((i + 1))
done
$magiskboot repack $PWD/tools/boot.img
$bbox dd if=new-boot.img of=/dev/block/bootdevice/by-name/boot

ui_print " " "Change Screen Refresh Rate and CPU offset"

$bbox rm -f kernel_dtb-*
$bbox rm -f new-boot.img
