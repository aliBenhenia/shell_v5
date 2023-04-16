#include "minishell.h"
t_export	*addnew1(char *var, char *value)
{
	t_export	*new;

	new = malloc(sizeof(t_export));
	if (!new)
		return (NULL);
	new->var = var;
	new->value = value;
	new->next = NULL;
	return (new);
}
void	addback_export1(t_export **a, t_export *new)
{
  t_export  *head;
static int i = 1;
    if(i++ == 1)
    {
        (*a) = new;
    }
    else
    {
        head = (*a);
        new->next = NULL;
        head = (*a);
        while (head->next)
        {
            head = head->next;
        }
        head->next = new;
    }
}

t_env_list	*addnew2_1(char *var, char *value)
{
	t_env_list	*new;

	new = malloc(sizeof(t_env_list));
	if (!new)
		return (NULL);
	new->name = var;
	new->value = value;
	new->next = NULL;
	return (new);
}
void	addback_env2(t_env_list **a, t_env_list *new)
{
   t_env_list  *head;

    new->next = NULL;
    head = (*a);
    if(head == NULL)
    {
         (*a) = new;
    }
    else
    { 
        head = (*a);
        while (head->next)
            head = head->next;
        head->next = new;
    }
}
void insert(t_export** head, t_export* new_node) {
    t_export* current;
    
    if (*head == NULL || strcmp((*head)->var, new_node->var) > 0) {
        new_node->next = *head;
        *head = new_node;
    } else {
        current = *head;
        while (current->next != NULL && strcmp(current->next->var, new_node->var) < 0)
        {
            current = current->next;
        }
        new_node->next = current->next;
        current->next = new_node;
    }
}
void sort(t_export ** head) {
   t_export * sorted = NULL;
   t_export * current = *head;
   t_export * next;
    
    while (current != NULL) {
        next = current->next;
        insert(&sorted, current);
        current = next;
    }
    
    *head = sorted;
}
void    init_env(t_export **export,t_env_list **env_list, char *env[])
{
    int i;
    char **var_val;
    i = 0;
    t_export *new;
    t_export *head_export;
    t_export *head_export2;
    t_export *temp;
    t_env_list *new1;
    while (env[i])
    {
        var_val = ft_split(env[i],'=');
        new = addnew1(var_val[0],var_val[1]);
        addback_export1(export, new);
        new1 = addnew2_1(var_val[0],var_val[1]);
        addback_env2(env_list, new1);
        i++;
    }
    sort(export);
}