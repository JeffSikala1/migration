for i in vaswr01 pgollt01 nelsd01 pamas01 tatre01 nelsd01 jangr01 barur01 philt01 thaip01 bakta01 dales01 hylaj01 zehej01
do
    mkdir ~$i/.ssh
    cp $i.pub ~$i/.ssh/authorized_keys
    chown -R $i:$i ~$i/.ssh*
    chmod 700 ~$i/.ssh
    chmod 600 ~$i/.ssh/authorized_keys
done
