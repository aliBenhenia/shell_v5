#include "minishell.h"
void removeNode2(t_env_list **env, char *str)
{
	t_env_list	*head;
	t_env_list	*temp;

	head = (*env);
	if(head == NULL)
		return;
	if(head != NULL && ft_strcmp(head->name,str) == 0)
	{
		temp = (*env);
		(*env) = (*env)->next;
		free(temp);
		return ;
	}
	while (head != NULL && head->next != NULL)
	{
		if (ft_strcmp(head->next->name,str) == 0)
		{
			temp = head->next;
			head->next = temp->next;
			free(temp);
		}
		else
			head = head->next;
	}
}
void removeNode(t_export **export, char *str)
{
	t_export	*head;
	t_export	*temp;

	head = (*export);
	if(head == NULL)
		return;
	if(head != NULL && ft_strcmp(head->var,str) == 0)
	{
		temp = (*export);
		(*export) = (*export)->next;
		free(temp);
		return ;
	}
	while (head != NULL && head->next != NULL)
	{
		if (ft_strcmp(head->next->var,str) == 0)
		{
			temp = head->next;
			head->next = temp->next;
			free(temp);
		}
		else
			head = head->next;
	}
}

int	check_name_is_exist(char *s, t_export *export)
{
	t_export	*head;

	head = export;
	while (head)
	{
		if(ft_strcmp(head->var,s) == 0)
			return (1);
		head = head->next;
	}
	return(0);
}

void    do_unset(char *str[],t_export **data, t_env_list **env_list)
{
	int	i;

	if (str[1] == NULL)
		return ;
	i = 1;
	while (str[i])
	{
		if(check_name_is_exist(str[i],(*data)))
		{
			removeNode(data,str[i]);
			removeNode2(env_list,str[i]);
		}
		else
			error_od_export(str[i]);
		i++;
	}
}