#!/bin/bash

scrp_path=$(cd `dirname $0`; pwd)
. ${scrp_path}/utils.sh

################################################################

show_usage() {
    appname=$0
    echo_warn "Usage:"
    echo_warn "  ${appname} [base|dpu] [reduce|group]"
    echo_warn "  ${appname} stop"
}

stop_dpu() {
    
    echo_info "Stopping DPU..."
    for worker_id in ${worker_ids[@]}
    do
        pid=`ssh ${username}@${remote_net}.${worker_id} "ssh ${dpu_from_host} pgrep dpu_test"`
        if [ ! $pid ]; then
            echo_warn "DPU not running on ${remote_net}.${worker_id}"
        else
            echo_back "ssh ${username}@${remote_net}.${worker_id} 'ssh ${dpu_from_host} sudo kill -15 ${pid}'"
        fi
        sleep 0.5
    done
    sleep 5
}

stop_spark() {
    echo_back "${SPARK_HOME}/sbin/stop-all.sh"
}

set_slaves() 
{
    for loop in ${!worker_ids[@]}
    do
        worker_id=${worker_ids[${loop}]}
        if [ $loop -eq 0 ]; then
            echo_back "sudo sh -c 'echo ${remote_net}.${worker_id} > ${SPARK_HOME}/conf/slaves'"
        else
            echo_back "sudo sh -c 'echo ${remote_net}.${worker_id} >> ${SPARK_HOME}/conf/slaves'"
        fi

        echo_back "ssh ${remote_net}.${worker_id} 'echo SPARK_MASTER_HOST=${MASTER}|sudo tee ${SPARK_HOME}/conf/spark-env.sh'"
        # echo_back "ssh ${remote_net}.${worker_id} 'echo SPARK_LOCAL_IP=${remote_net}.${worker_id}|sudo tee -a ${SPARK_HOME}/conf/spark-env.sh'"
    done
    # echo_back "cat ${SPARK_HOME}/conf/slaves"
}

start_spark() {
    echo_back "${SPARK_HOME}/sbin/start-all.sh"
}

start_dpu() {
    method=$1
    for worker_id in ${worker_ids[@]}
    do
        case $method in
            "dpu")
                # echo_back "ssh ${username}@${remote_net}.${worker_id} 'sudo sh -c '\''${remote_tar_path}/dpu-sparkdpu > ${remote_tar_path}/dpdk_${worker_id}.txt 2>&1 &'\'''"
                echo_back "ssh ${username}@${remote_net}.${worker_id} 'ssh ${dpu_from_host} '\"'${dpu_tar_path}/dpu_test -p 03:00.0 -r 01:00.0 > ${dpu_tar_path}/dpu_${worker_id}.txt 2>&1 &'\"''"
                ;;
            *)
                echo_erro "method name must be dpu"
                exit 1
                ;;
        esac
        sleep 0.5
    done
    sleep 5
    for worker_id in ${worker_ids[@]}
    do
        pid=`ssh ${username}@${remote_net}.${worker_id} "ssh ${dpu_from_host} pgrep dpu_test"`
        if [ ! $pid ]; then
            echo_warn "DPU not running on ${remote_net}.${worker_id}"
        fi
        sleep 0.5
    done
}

run_base() {
    
    MASTER=$1
    DRIMEM=$2
    EXEMEM=$3
    NUM_WORKER=$4
    NUM_MAPPER_PER_WORKER=$5
    NUM_REDUCER_PER_WORKER=$6
    NUM_KV=$7
    NUM_KEY=$8
    APP_PATH=$9
    # input_file=$7

    echo_back "${SPARK_HOME}/bin/spark-submit \
--class 'WordCount' \
--deploy-mode client \
--master spark://${MASTER}:7077 \
--driver-memory ${DRIMEM} \
--executor-memory ${EXEMEM} \
--conf spark.driver.extraClassPath=${remote_tar_path}/spark-base-1.0-for-spark-2.3.0-jar-with-dependencies.jar \
--conf spark.driver.extraLibraryPath=${remote_tar_path} \
--conf spark.executor.extraClassPath=${remote_tar_path}/spark-base-1.0-for-spark-2.3.0-jar-with-dependencies.jar \
--conf spark.executor.extraLibraryPath=${remote_tar_path} \
--conf spark.shuffle.manager=org.apache.spark.shuffle.sort.MysortShuffleManager \
--conf spark.executor.cores=${NUM_MAPPER_PER_WORKER} \
${APP_PATH} \
${NUM_WORKER} ${NUM_MAPPER_PER_WORKER} ${NUM_REDUCER_PER_WORKER} ${NUM_KV} ${NUM_KEY} > ${remote_tar_path}/driver_log 2>&1"
}


run_dpu() {
    MASTER=$1
    DRIMEM=$2
    EXEMEM=$3
    NUM_WORKER=$4
    NUM_MAPPER_PER_WORKER=$5
    NUM_REDUCER_PER_WORKER=$6
    NUM_KV=$7
    NUM_KEY=$8
    APP_PATH=$9
    # input_file=$7
    echo_back "export LD_PRELOAD='librt.so'"
    # echo_back "export LD_SPARK_DPU='${remote_tar_path}/libspark_dpu.so'"
    echo_back "${SPARK_HOME}/bin/spark-submit \
--class 'WordCount' \
--deploy-mode client \
--master spark://${MASTER}:7077 \
--driver-memory ${DRIMEM} \
--executor-memory ${EXEMEM} \
--conf spark.driver.extraClassPath=${remote_tar_path}/spark-dpu-1.0-for-spark-2.3.0-jar-with-dependencies.jar \
--conf spark.driver.extraLibraryPath=${remote_tar_path} \
--conf spark.executor.extraClassPath=${remote_tar_path}/spark-dpu-1.0-for-spark-2.3.0-jar-with-dependencies.jar \
--conf spark.executor.extraLibraryPath=${remote_tar_path} \
--conf spark.shuffle.manager=org.apache.spark.shuffle.aggr.AGGRShuffleManager \
--conf spark.shuffle.compress=false \
--conf spark.executor.cores=${NUM_MAPPER_PER_WORKER} \
${APP_PATH} \
${NUM_WORKER} ${NUM_MAPPER_PER_WORKER} ${NUM_REDUCER_PER_WORKER} ${NUM_KV} ${NUM_KEY} > ${remote_tar_path}/driver_log 2>&1"
    echo_back "export LD_PRELOAD=''"
}

show_result() {
    time_used=`grep -n 'Job 1 finished' ${remote_tar_path}/driver_log | awk '{printf $13 '\"'\n'\"'}'`
    
    for worker_id in ${worker_ids[@]}
    do
        echo_back "ssh ${username}@${remote_net}.${worker_id} 'scp ${dpu_from_host}:${dpu_tar_path}/dpu_${worker_id}.txt ${remote_tar_path}'"
        echo_back "scp ${username}@${remote_net}.${worker_id}:${remote_tar_path}/dpu_${worker_id}.txt ${remote_tar_path}"
    done
    echo_info "Time used : ${time_used} s"
}

test_xxx() {
    method=$1
    app=$2
    
    MASTER=${remote_net}.${worker_ids[0]}
    NUM_WORKER=${#worker_ids[@]}

    case $app in
        "reduce")
            APP_PATH=${remote_tar_path}/reduceby-word-count_2.11-1.0.jar
            ;;
        "group")
            APP_PATH=${remote_tar_path}/groupby-word-count_2.11-1.0.jar
            ;;
        *)
            echo_erro "Unknown app name : ${app}"
            exit 1
            ;;
    esac

    stop_spark
    stop_dpu

    set_slaves
    
    sleep 1
    start_spark
    sleep 1

    case $method in
        "base")
            run_base ${MASTER} ${DRIMEM} ${EXEMEM} ${NUM_WORKER} ${NUM_MAPPER_PER_WORKER} ${NUM_REDUCER_PER_WORKER} ${NUM_KV} ${NUM_KEY} ${APP_PATH}
            ;;
        "dpu")
            start_dpu ${method}

            run_dpu ${MASTER} ${DRIMEM} ${EXEMEM} ${NUM_WORKER} ${NUM_MAPPER_PER_WORKER} ${NUM_REDUCER_PER_WORKER} ${NUM_KV} ${NUM_KEY} ${APP_PATH}
            ;;
    esac

    show_result

    stop_spark
    stop_dpu

    sleep 5
}

cleanlog() {
    for worker_id in ${worker_ids[@]}
    do
        echo_back "ssh ${username}@${remote_net}.${worker_id} 'sudo rm -rf ${SPARK_HOME}/work/app-*'"
    done
}

if [ $# -eq 0 ]; then
    show_usage
else
    all_args=($*)
    inner_args=${all_args[*]:1:$#}
    case $1 in
        "base")
            test_xxx "base" $2
            ;;
        "dpu")
            test_xxx "dpu" $2
            ;;
        "stop")
            stop_spark
            stop_dpu
            ;;
        "startspark")
            MASTER=${remote_net}.1
            set_slaves
            start_spark
            ;;
        "cleanlog")
            cleanlog
            ;;
        *)
            show_usage
            ;;
    esac
fi
