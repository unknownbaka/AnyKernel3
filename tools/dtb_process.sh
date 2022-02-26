#!/sbin/sh
#Thank lyq1996
home=$PWD/..
dtc=$home/tools/dtc
dtp=$home/tools/dtp
bbox=$home/tools/busybox

file_getprop() { $bbox grep "^$2=" "$1" | $bbox cut -d= -f2-; }
screen=$(file_getprop $home/anykernel.sh do.refresh_rate)
dts_backup=$(file_getprop $home/anykernel.sh do.dts_backup)
screen=${screen:="0"}
dts_backup=${dts_backup:="0"}

ui_print() {
  until [ ! "$1" ]; do
    echo -e "ui_print $1
      ui_print" >> /proc/self/fd/$OUTFD;
    shift;
  done;
}

if [ -e kernel_dtb ]; then
    tag=0
else
    mv kernel kernel_dtb
    tag=1
fi
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
	$dtc -q -I dtb -O dts kernel_dtb-$i -o kernel_dtb_$i.dts
	dts_board_id=$($bbox cat kernel_dtb_$i.dts | $bbox grep qcom,board-id | $bbox sed -e 's/[\t]*qcom,board-id = <//g' | $bbox sed 's/>;//g')
	dts_msm_id=$($bbox cat kernel_dtb_$i.dts | $bbox grep qcom,msm-id | $bbox sed -e 's/[\t]*qcom,msm-id = <//g' | $bbox sed 's/>;//g')
	if [ "$dts_board_id" = "$board_id" ] && [ "$dts_msm_id" = "$msm_id" ]; then
		break
	fi
	$bbox rm -f kernel_dtb_$i.dts
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
    ui_print " " "Changing screen refresh rate..."
    ui_print "$screen"
	srr=qcom,mdss-dsi-panel-framerate
	max_srr=qcom,mdss-dsi-max-refresh-rate
	new_ssr_=$(printf "0x%x" $screen)
	$bbox sed -i "s/$srr = <[^)]*>/$srr = <$new_ssr_>/g" kernel_dtb_$i.dts
	$bbox sed -i "s/$max_srr = <[^)]*>/$max_srr = <$new_ssr_>/g" kernel_dtb_$i.dts
fi

# backup dts
if [ "$dts_backup" = "1" ]; then
    ui_print " " "Backuping dts......"
    ui_print "/sdcard/Android/backup.dts"
	$bbox cp kernel_dtb_$i.dts /sdcard/Android/backup.dts
fi

# compile dts to dtb
$dtc -q -I dts -O dtb kernel_dtb_$i.dts -o kernel_dtb-$i

# generate new dtb
i=0
> kernel_dtb
while [ $i -lt $dtb_count ]; do
	$bbox cat kernel_dtb-$i >> kernel_dtb
	i=$((i + 1))
done

if [ "$tag" = "1" ]; then
    mv kernel_dtb kernel
fi

$bbox rm -f kernel_dtb-*