#! /bin/sh
#
# mongooseim        Start/stop mongooseim server
#

### BEGIN INIT INFO
# Provides:          mongooseim
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start daemon at boot time
# Description:       Enable service provided by daemon.
### END INIT INFO

RUNNER_BASE_DIR=/usr/lib/mongooseim
RUNNER_ETC_DIR=$RUNNER_BASE_DIR/etc
RUNNER_LOG_DIR=$RUNNER_BASE_DIR/log
# Note the trailing slash on $PIPE_DIR/
PIPE_DIR=/tmp/$RUNNER_BASE_DIR/
RUNNER_USER=mongooseim

mongooseim_SO_PATH=$RUNNER_BASE_DIR/lib/mongooseim-2.1.8/priv/lib
mongooseim_CONFIG_PATH=$RUNNER_ETC_DIR/mongooseim.cfg
export mongooseim_SO_PATH
export mongooseim_CONFIG_PATH

# Make sure this script is running as the appropriate user
if [ ! -z "$RUNNER_USER" ] && [ `whoami` != "$RUNNER_USER" ]; then
    exec sudo -u $RUNNER_USER -i $0 $@
fi

# Make sure CWD is set to runner base dir
cd $RUNNER_BASE_DIR

# Make sure log directory exists
mkdir -p $RUNNER_LOG_DIR

# Extract the target node name from node.args
NAME_ARG=`egrep -e '^-s?name' $RUNNER_ETC_DIR/vm.args`
if [ -z "$NAME_ARG" ]; then
    echo "vm.args needs to have either -name or -sname parameter."
    exit 1
fi

# Extract the target cookie
COOKIE_ARG=`grep -e '^-setcookie' $RUNNER_ETC_DIR/vm.args`
if [ -z "$COOKIE_ARG" ]; then
    echo "vm.args needs to have a -setcookie parameter."
    exit 1
fi

# Identify the script name
SCRIPT=mongooseim

# Parse out release and erts info
START_ERL=`cat $RUNNER_BASE_DIR/releases/start_erl.data`
ERTS_VSN=${START_ERL% *}
APP_VSN=${START_ERL#* }

# Add ERTS bin dir to our path
ERTS_PATH=$RUNNER_BASE_DIR/erts-$ERTS_VSN/bin

# Setup command to control the node
NODETOOL="$ERTS_PATH/escript $ERTS_PATH/nodetool $NAME_ARG $COOKIE_ARG"

# Check the first argument for instructions
case "$1" in
    start)
        # Make sure there is not already a node running
        RES=`$NODETOOL ping`
        if [ "$RES" = "pong" ]; then
            echo "Node is already running!"
            exit 1
        fi
        HEART_COMMAND="$RUNNER_BASE_DIR/bin/$SCRIPT start"
        export HEART_COMMAND
        mkdir -p $PIPE_DIR
        shift # remove $1
        $ERTS_PATH/run_erl -daemon $PIPE_DIR $RUNNER_LOG_DIR "exec $RUNNER_BASE_DIR/bin/$SCRIPT console $@" 2>&1
        ;;

    stop)
        # Wait for the node to completely stop...
        case `uname -s` in
            Linux|Darwin|FreeBSD|DragonFly|NetBSD|OpenBSD)
                # PID COMMAND
                PID=`ps ax -o pid= -o command=|\
                    grep "$RUNNER_BASE_DIR/.*/[b]eam"|awk '{print $1}'`
                ;;
            SunOS)
                # PID COMMAND
                PID=`ps -ef -o pid= -o args=|\
                    grep "$RUNNER_BASE_DIR/.*/[b]eam"|awk '{print $1}'`
                ;;
            CYGWIN*)
                # UID PID PPID TTY STIME COMMAND
                PID=`ps -efW|grep "$RUNNER_BASE_DIR/.*/[b]eam"|awk '{print $2}'`
                ;;
        esac
        $NODETOOL stop
        while `kill -0 $PID 2>/dev/null`;
        do
            sleep 1
        done
        ;;

    restart)
        ## Restart the VM without exiting the process
        $NODETOOL restart
        ;;

    reboot|force-reload)
        ## Restart the VM completely (uses heart to restart it)
        $NODETOOL reboot
        ;;

    ping)
        ## See if the VM is alive
        $NODETOOL ping
        ;;

    status)
        RES=`$NODETOOL ping`
        if [ "$RES" = "pong" ]; then
            echo "Node is running"
        else
        	echo "Node is not running!"
        	exit 3
        fi
        ;;    

    attach)
        # Make sure a node IS running
        RES=`$NODETOOL ping`
        if [ "$RES" != "pong" ]; then
            echo "Node is not running!"
            exit 1
        fi

        shift
        $ERTS_PATH/to_erl $PIPE_DIR
        ;;

    console|live|console_clean)
        # .boot file typically just $SCRIPT (ie, the app name)
        # however, for debugging, sometimes start_clean.boot is useful:
        case "$1" in
            console|live)   BOOTFILE=$SCRIPT ;;
            console_clean)  BOOTFILE=start_clean ;;
        esac
        # Setup beam-required vars
        ROOTDIR=$RUNNER_BASE_DIR
        BINDIR=$ROOTDIR/erts-$ERTS_VSN/bin
        EMU=beam
        PROGNAME=`echo $0 | sed 's/.*\\///'`
        CMD="$BINDIR/erlexec -boot $RUNNER_BASE_DIR/releases/$APP_VSN/$BOOTFILE -embedded -config $RUNNER_ETC_DIR/app.config -args_file $RUNNER_ETC_DIR/vm.args -- ${1+"$@"}"
        export EMU
        export ROOTDIR
        export BINDIR
        export PROGNAME

        # Dump environment info for logging purposes
        echo "Exec: $CMD"
        echo "Root: $ROOTDIR"

        # Log the startup
        logger -t "$SCRIPT[$$]" "Starting up"

        # Start the VM
        exec $CMD
        ;;

    debug)
        echo "--------------------------------------------------------------------"
        echo ""
        echo "IMPORTANT: we will attempt to attach an INTERACTIVE shell"
        echo "to an already running mongooseim node."
        echo "If an ERROR is printed, it means the connection was not successful."
        echo "You can interact with the mongooseim node if you know how to use it."
        echo "Please be extremely cautious with your actions,"
        echo "and exit immediately if you are not completely sure."
        echo ""
        echo "To detach this shell from mongooseim, press:"
        echo "  control+c, control+c"
        echo ""
        echo "--------------------------------------------------------------------"
        echo "Press 'Enter' to continue"
        read
        echo ""
        NAME=$(echo $NAME_ARG | awk '{print $1}')
        NODE=$(echo $NAME_ARG | awk '{print $2}')
        TTY=$(basename `tty`)

        ROOTDIR=$RUNNER_BASE_DIR
        BINDIR=$ROOTDIR/erts-$ERTS_VSN/bin
        PROGNAME=`echo $0 | sed 's/.*\\///'`
        CMD="$BINDIR/erl $NAME debug-$TTY-$NODE $COOKIE_ARG -remsh $NODE -hidden"

        # Log the startup
        logger -t "$SCRIPT[$$]" "Starting up"

        # Start the VM
        exec $CMD
        ;;
    *)
        echo "Usage: $SCRIPT {start|stop|restart|reboot|ping|live|console|console_clean|attach|debug|status}"
        exit 1
        ;;
esac

exit 0
