# Check pre-requisites are installed.
echo "true" | jq > /dev/null
if [[ $? -ne 0 ]]; then
  echo "Missing required utility 'jq'"
  echo "please run 'brew install jq'"
  exit 127
fi

# Store a backup of config and credentials.
cp ~/.aws/config ~/.aws/config.bak
cp ~/.aws/credentials ~/.aws/credentials.bak

prompt_confirm() {
  while true; do
    read -r -n 1 -p "${1:-Continue?} [y/n]: " REPLY
    case $REPLY in
      [yY]) echo ; return 0 ;;
      [nN]) echo ; return 1 ;;
      *) printf " \033[31m %s \n\033[0m" "invalid input, please enter 'y' or 'n'"
    esac 
  done  
}
timer_bar() {
  cols=`tput cols`
  x=`bc -l <<< "$1 / $cols"`
  for i in $(seq 1 $cols)
  do
    echo -n "#"
    sleep $x # (5 / 80, 5 is number of seconds to wait total)
  done
  echo ""
}

PROFILES="$1 $2 $3"
if [[ -z `echo $PROFILES` ]]; then
    echo "Using default profiles"
    PROFILES="playground staging production"
fi

if [[ "$PROFILES" != *"playground"* ]]; then
  echo "Expected at least 'playground' in the profiles list!"
  exit 1
fi

echo "Generate credentials for the profiles [$PROFILES]"

old_keys=""
for profile in $PROFILES
do
  # Get info for old key so we can clean it up.
  echo "Getting old key info for $profile"
  
  old_key_info=`aws iam list-access-keys --profile "$profile"`
  num_existing_keys=`echo "$old_key_info" | jq -r '.AccessKeyMetadata | length'`
  if [ "$num_existing_keys" -ne "1" ]; then
    # This limitation is because:
    #  Techops policy is to only allow 2 keys max so it will fail to
    #   create the new one. Arguably we should get the existing key
    #   id from the ~/.aws/credentials file instead of list-access-keys.
    echo "Expected only 1 existing key but found $num_existing_keys"
    echo "You can list existing keys with the command:"
    echo "aws iam list-access-keys --profile \"$profile\""
    echo "You can delete existing keys with the command:"
    echo "aws iam delete-access-key --access-key <key id> --user-name <username> --profile \"$profile\""
    exit 2
  fi
  old_key_user_name=`echo "$old_key_info" | jq -r '.AccessKeyMetadata[0].UserName'`
  old_key_id=`echo "$old_key_info" | jq -r '.AccessKeyMetadata[0].AccessKeyId'`
  
  echo "Creating new key for $profile"
  
  key_info=`aws iam create-access-key --profile "$profile"`
  key_id=`echo $key_info | jq -r .AccessKey.AccessKeyId`
  secret=`echo $key_info | jq -r .AccessKey.SecretAccessKey`
  
  echo "Configuring profile in ~/.aws/credentials for $profile"
  
  aws configure set aws_access_key_id "$key_id" --profile "$profile"
  aws configure set aws_secret_access_key "$secret" --profile "$profile"
  
  old_keys="$old_keys $profile,$old_key_user_name,$old_key_id"
  timer_bar 2
done

echo "Setting playground credentials as default"
# Set default to playground credentials
aws configure set aws_access_key_id `aws configure get aws_access_key_id --profile playground`
aws configure set aws_secret_access_key `aws configure get aws_secret_access_key --profile playground`

# Wait for some time, AWS needs some time before the credentials are usable.

prompt_confirm "Remove Old Keys?" || exit 0

for i in $old_keys
do
  IFS=',' read profile old_key_user_name old_key_id <<< "${i}"
  echo "Removing old $profile key ($old_key_user_name/$old_key_id)"
  # For some reason this doesnt seem to be working at the moment (An error occurred (InvalidClientTokenId) when calling the DeleteAccessKey operation: The security token included in the request is invalid.)
  aws iam delete-access-key --access-key "$old_key_id" --user-name "$old_key_user_name" --profile "$profile"
done